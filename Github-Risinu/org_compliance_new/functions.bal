import ballerina/lang.array;
import ballerina/lang.regexp;
import ballerina/time;
import ballerinax/github;

// Fixed branch name used for compliance remediation so repeated runs reuse the same branch
// instead of creating duplicates.
final string remediationBranchName = "compliance/remediation";

// Candidate locations where a CODEOWNERS file may live, in the order GitHub itself checks them.
final string[] codeownersLocations = [".github/CODEOWNERS", "docs/CODEOWNERS", "CODEOWNERS"];

// Patterns that indicate a hardcoded secret/token was committed directly into a workflow file,
// instead of being referenced via `secrets.*` or an environment variable.
final regexp:RegExp[] hardcodedTokenPatterns = [
    re `ghp_[A-Za-z0-9]{20,}`,
    re `gho_[A-Za-z0-9]{20,}`,
    re `ghu_[A-Za-z0-9]{20,}`,
    re `ghs_[A-Za-z0-9]{20,}`,
    re `ghr_[A-Za-z0-9]{20,}`,
    re `github_pat_[A-Za-z0-9_]{20,}`,
    re `xox[baprs]-[A-Za-z0-9-]{10,}`,
    re `AKIA[A-Z0-9]{16}`,
    re `AIza[A-Za-z0-9_-]{35}`,
    re `sk-[A-Za-z0-9]{20,}`
];

// Fetches every non-archived repository in the org, paging through the results properly.
function fetchNonArchivedRepositories(string org) returns github:MinimalRepository[]|error {
    github:MinimalRepository[] nonArchivedRepositories = [];
    int currentPage = 1;
    int perPage = 100;
    while true {
        github:MinimalRepository[] pageOfRepositories = check githubClient->/orgs/[org]/repos(perPage = perPage, page = currentPage, 'type = "all");
        if pageOfRepositories.length() == 0 {
            break;
        }
        foreach github:MinimalRepository repository in pageOfRepositories {
            boolean archived = repository.archived ?: false;
            if !archived {
                nonArchivedRepositories.push(repository);
            }
        }
        if pageOfRepositories.length() < perPage {
            break;
        }
        currentPage += 1;
    }
    return nonArchivedRepositories;
}

// Checks that the default branch has protection enabled with at least one required approving
// review and required status checks. A 403 (no admin rights) is reported as "unknown" rather
// than failing the whole scan.
function checkBranchProtection(string owner, string repo, string defaultBranch) returns BranchProtectionCheck {
    github:BranchProtection|error branchProtection = githubClient->/repos/[owner]/[repo]/branches/[defaultBranch]/protection;
    if branchProtection is error {
        string errorMessage = branchProtection.message();
        if errorMessage.includes("403") {
            return {
                status: "unknown",
                requiresApprovingReview: false,
                requiredApprovingReviewCount: 0,
                requiresStatusChecks: false,
                details: "Insufficient permissions (403) to read branch protection; admin rights required"
            };
        }
        return {
            status: "fail",
            requiresApprovingReview: false,
            requiredApprovingReviewCount: 0,
            requiresStatusChecks: false,
            details: string `Failed to fetch branch protection: ${errorMessage}`
        };
    }

    github:ProtectedBranchPullRequestReview? pullRequestReview = branchProtection.requiredPullRequestReviews;
    int requiredApprovingReviewCount = 0;
    if pullRequestReview is github:ProtectedBranchPullRequestReview {
        requiredApprovingReviewCount = pullRequestReview.requiredApprovingReviewCount ?: 0;
    }
    boolean requiresApprovingReview = requiredApprovingReviewCount >= 1;

    github:ProtectedBranchRequiredStatusCheck? requiredStatusCheck = branchProtection.requiredStatusChecks;
    boolean requiresStatusChecks = requiredStatusCheck is github:ProtectedBranchRequiredStatusCheck;

    if requiresApprovingReview && requiresStatusChecks {
        return {
            status: "pass",
            requiresApprovingReview,
            requiredApprovingReviewCount,
            requiresStatusChecks,
            details: "Branch protection enabled with required approving review and required status checks"
        };
    }

    string[] missingItems = [];
    if !requiresApprovingReview {
        missingItems.push("at least one required approving review");
    }
    if !requiresStatusChecks {
        missingItems.push("required status checks");
    }
    string missingList = string:'join(", ", ...missingItems);
    return {
        status: "fail",
        requiresApprovingReview,
        requiredApprovingReviewCount,
        requiresStatusChecks,
        details: string `Branch protection is missing: ${missingList}`
    };
}

// Checks whether a CODEOWNERS file exists in .github/, docs/, or the repo root.
function checkCodeowners(string owner, string repo) returns CodeownersCheck {
    foreach string location in codeownersLocations {
        github:ContentDirectory|github:ContentFile|github:ContentSymlink|github:ContentSubmodule|error?|() content = githubClient->/repos/[owner]/[repo]/contents/[location];
        if content is github:ContentFile {
            return {
                status: "pass",
                location,
                details: string `CODEOWNERS file found at ${location}`
            };
        }
    }
    return {
        status: "fail",
        location: "",
        details: "No CODEOWNERS file found in .github/, docs/, or the repo root"
    };
}

// Checks whether a LICENSE file exists for the repository.
function checkLicense(string owner, string repo) returns LicenseCheck {
    github:LicenseContent|error license = githubClient->/repos/[owner]/[repo]/license;
    if license is github:LicenseContent {
        return {
            status: "pass",
            details: string `LICENSE file found at ${license.path}`
        };
    }
    return {
        status: "fail",
        details: "No LICENSE file found"
    };
}

// Checks that the repository has at least one topic.
function checkTopics(string owner, string repo) returns TopicsCheck {
    github:Topic|error topicResult = githubClient->/repos/[owner]/[repo]/topics;
    if topicResult is error {
        return {
            status: "fail",
            topicCount: 0,
            details: string `Failed to fetch topics: ${topicResult.message()}`
        };
    }
    int topicCount = topicResult.names.length();
    if topicCount >= 1 {
        return {
            status: "pass",
            topicCount,
            details: string `Repository has ${topicCount} topic(s)`
        };
    }
    return {
        status: "fail",
        topicCount,
        details: "Repository has no topics"
    };
}

// Scans a single workflow file's content for hardcoded token patterns.
function workflowContainsHardcodedToken(string owner, string repo, string workflowPath) returns boolean|error {
    github:ContentDirectory|github:ContentFile|github:ContentSymlink|github:ContentSubmodule|error?|() content = check githubClient->/repos/[owner]/[repo]/contents/[workflowPath];
    if content is github:ContentFile {
        string base64Content = re `\n`.replaceAll(content.content, "");
        byte[]|error decodedBytes = array:fromBase64(base64Content);
        if decodedBytes is error {
            return decodedBytes;
        }
        string|error decodedContent = string:fromBytes(decodedBytes);
        if decodedContent is error {
            return decodedContent;
        }
        foreach regexp:RegExp tokenPattern in hardcodedTokenPatterns {
            if tokenPattern.isFullMatch(decodedContent) || tokenPattern.find(decodedContent) is regexp:Span {
                return true;
            }
        }
    }
    return false;
}

// Checks that no workflow file under .github/workflows contains a hardcoded token pattern.
function checkWorkflowTokens(string owner, string repo) returns WorkflowTokenScanCheck {
    github:WorkflowResponse|error workflowResponse = githubClient->/repos/[owner]/[repo]/actions/workflows(perPage = 100);
    if workflowResponse is error {
        return {
            status: "fail",
            flaggedWorkflows: [],
            details: string `Failed to list workflows: ${workflowResponse.message()}`
        };
    }

    github:Workflow[] workflows = workflowResponse.workflows;
    if workflows.length() == 0 {
        return {
            status: "pass",
            flaggedWorkflows: [],
            details: "No workflow files found"
        };
    }

    string[] flaggedWorkflows = [];
    foreach github:Workflow workflow in workflows {
        boolean|error scanResult = workflowContainsHardcodedToken(owner, repo, workflow.path);
        if scanResult is error {
            continue;
        }
        if scanResult {
            flaggedWorkflows.push(workflow.path);
        }
    }

    if flaggedWorkflows.length() == 0 {
        return {
            status: "pass",
            flaggedWorkflows: [],
            details: "No hardcoded token patterns found in workflow files"
        };
    }
    string flaggedList = string:'join(", ", ...flaggedWorkflows);
    return {
        status: "fail",
        flaggedWorkflows,
        details: string `Hardcoded token pattern(s) found in: ${flaggedList}`
    };
}

// Runs every compliance rule against a single repository and aggregates the results.
function scanRepository(github:MinimalRepository repository) returns RepositoryComplianceResult {
    string owner = repository.owner.login;
    string repoName = repository.name;
    string defaultBranch = repository.defaultBranch ?: "main";

    BranchProtectionCheck branchProtectionCheck = checkBranchProtection(owner, repoName, defaultBranch);
    CodeownersCheck codeownersCheck = checkCodeowners(owner, repoName);
    LicenseCheck licenseCheck = checkLicense(owner, repoName);
    TopicsCheck topicsCheck = checkTopics(owner, repoName);
    WorkflowTokenScanCheck workflowTokenScanCheck = checkWorkflowTokens(owner, repoName);

    RepositoryComplianceChecks checks = {
        branchProtection: branchProtectionCheck,
        codeowners: codeownersCheck,
        license: licenseCheck,
        topics: topicsCheck,
        workflowTokenScan: workflowTokenScanCheck
    };

    boolean compliant = branchProtectionCheck.status != "fail" &&
        codeownersCheck.status != "fail" &&
        licenseCheck.status != "fail" &&
        topicsCheck.status != "fail" &&
        workflowTokenScanCheck.status != "fail";

    return {
        name: repoName,
        fullName: repository.fullName,
        defaultBranch,
        compliant,
        checks
    };
}

// Renders a CODEOWNERS file from the configured path-pattern-to-owner mapping.
function generateCodeownersContent(map<string> teamMapping) returns string {
    string content = "# Auto-generated by the compliance remediation service.\n" +
        "# Maps file path patterns to their owning team/user.\n\n";
    foreach string pattern in teamMapping.keys() {
        string owner = teamMapping.get(pattern);
        content += string `${pattern} ${owner}` + "\n";
    }
    return content;
}

// Renders the Apache License 2.0 text with the copyright year and holder filled in.
function generateApache2LicenseContent(string copyrightHolder) returns string {
    time:Utc currentUtc = time:utcNow();
    time:Civil currentCivil = time:utcToCivil(currentUtc);
    int currentYear = currentCivil.year;
    string licenseBody = string `                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing
      the origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright ${currentYear} ${copyrightHolder}

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
`;
    return licenseBody;
}

// Returns the current blob SHA of a file on the given branch, or () if the file does not exist
// on that branch yet.
function getFileShaOnBranch(string owner, string repo, string path, string branch) returns string?|error {
    github:ContentDirectory|github:ContentFile|github:ContentSymlink|github:ContentSubmodule|error?|() content = githubClient->/repos/[owner]/[repo]/contents/[path](ref = branch);
    if content is github:ContentFile {
        return content.sha;
    }
    if content is error {
        string errorMessage = content.message();
        if errorMessage.includes("404") {
            return ();
        }
        return content;
    }
    return ();
}

// Creates or updates a file at the given path on the given branch through the contents API,
// base64-encoding the content and supplying the current blob SHA when the file already exists.
function createOrUpdateFile(string owner, string repo, string path, string contentText, string commitMessage, string branch) returns "created"|"updated"|error {
    string? existingSha = check getFileShaOnBranch(owner, repo, path, branch);
    string encodedContent = array:toBase64(contentText.toBytes());
    github:ContentspathBody payload = existingSha is string
        ? {message: commitMessage, content: encodedContent, branch, sha: existingSha}
        : {message: commitMessage, content: encodedContent, branch};
    github:FileCommit _ = check githubClient->/repos/[owner]/[repo]/contents/[path].put(payload);
    return existingSha is string ? "updated" : "created";
}

// Ensures the remediation branch exists off the default branch, reusing it if it already exists
// so repeated remediation runs commit onto the same branch instead of creating a duplicate.
function ensureRemediationBranch(string owner, string repo, string defaultBranch, string branchName) returns error? {
    github:GitRef|error existingBranchRef = githubClient->/repos/[owner]/[repo]/git/ref/["heads/" + branchName];
    if existingBranchRef is github:GitRef {
        return;
    }
    github:GitRef defaultBranchRef = check githubClient->/repos/[owner]/[repo]/git/ref/["heads/" + defaultBranch];
    string defaultBranchSha = defaultBranchRef.'object.sha;
    github:GitRefsBody refPayload = {
        ref: string `refs/heads/${branchName}`,
        sha: defaultBranchSha
    };
    github:GitRef _ = check githubClient->/repos/[owner]/[repo]/git/refs.post(refPayload);
}

// Looks up an existing open remediation pull request for the given branch, if one exists.
function findExistingRemediationPr(string owner, string repo, string branchName) returns github:PullRequestSimple?|error {
    string headFilter = string `${owner}:${branchName}`;
    github:PullRequestSimple[]|error? existingPrs = githubClient->/repos/[owner]/[repo]/pulls(head = headFilter, state = "open");
    if existingPrs is error {
        return existingPrs;
    }
    if existingPrs is github:PullRequestSimple[] && existingPrs.length() > 0 {
        return existingPrs[0];
    }
    return ();
}

// Builds the pull request body listing which compliance checks are being remediated.
function buildRemediationPrBody(string[] failedChecks) returns string {
    string checklist = "";
    foreach string failedCheck in failedChecks {
        checklist += string `- ${failedCheck}` + "\n";
    }
    return "This pull request was opened automatically to remediate the following failed compliance checks:\n\n" + checklist;
}

// Remediates a single repository: for any of CODEOWNERS/LICENSE that are missing, creates (or
// reuses) a remediation branch, commits the missing file(s), and opens (or updates) a pull
// request listing the remediated checks.
function remediateRepository(string owner, string repo) returns RemediationResult|RemediationNotNeeded|error {
    github:FullRepository repository = check githubClient->/repos/[owner]/[repo];
    string defaultBranch = repository.defaultBranch;

    CodeownersCheck codeownersCheck = checkCodeowners(owner, repo);
    LicenseCheck licenseCheck = checkLicense(owner, repo);

    boolean codeownersMissing = codeownersCheck.status == "fail";
    boolean licenseMissing = licenseCheck.status == "fail";

    if !codeownersMissing && !licenseMissing {
        return {
            message: string `Repository '${owner}/${repo}' already has both CODEOWNERS and LICENSE; no remediation needed`
        };
    }

    check ensureRemediationBranch(owner, repo, defaultBranch, remediationBranchName);

    RemediationFileChange[] filesChanged = [];
    string[] remediatedChecks = [];

    if codeownersMissing {
        string codeownersContent = generateCodeownersContent(codeownersTeamMapping);
        "created"|"updated" action = check createOrUpdateFile(owner, repo, ".github/CODEOWNERS", codeownersContent, "chore: add CODEOWNERS for compliance remediation", remediationBranchName);
        filesChanged.push({path: ".github/CODEOWNERS", action});
        remediatedChecks.push("CODEOWNERS");
    }

    if licenseMissing {
        string licenseContent = generateApache2LicenseContent(licenseCopyrightHolder);
        "created"|"updated" action = check createOrUpdateFile(owner, repo, "LICENSE", licenseContent, "chore: add LICENSE for compliance remediation", remediationBranchName);
        filesChanged.push({path: "LICENSE", action});
        remediatedChecks.push("LICENSE");
    }

    string prBody = buildRemediationPrBody(remediatedChecks);
    string prTitle = "chore: compliance remediation";

    github:PullRequestSimple? existingPr = check findExistingRemediationPr(owner, repo, remediationBranchName);
    if existingPr is github:PullRequestSimple {
        github:PullspullNumberBody updatePayload = {
            title: prTitle,
            body: prBody
        };
        github:PullRequest updatedPr = check githubClient->/repos/[owner]/[repo]/pulls/[existingPr.number].patch(updatePayload);
        return {
            owner,
            repo,
            branchName: remediationBranchName,
            filesChanged,
            pullRequestUrl: updatedPr.htmlUrl,
            pullRequestNumber: updatedPr.number,
            pullRequestAction: "updated",
            remediatedChecks
        };
    }

    github:RepoPullsBody createPayload = {
        title: prTitle,
        body: prBody,
        head: remediationBranchName,
        base: defaultBranch
    };
    github:PullRequest createdPr = check githubClient->/repos/[owner]/[repo]/pulls.post(createPayload);
    return {
        owner,
        repo,
        branchName: remediationBranchName,
        filesChanged,
        pullRequestUrl: createdPr.htmlUrl,
        pullRequestNumber: createdPr.number,
        pullRequestAction: "created",
        remediatedChecks
    };
}
