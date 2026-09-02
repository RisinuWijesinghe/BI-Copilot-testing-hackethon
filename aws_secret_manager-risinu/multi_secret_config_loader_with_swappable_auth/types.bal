# Holds the secrets that were successfully loaded during startup, keyed by
# the logical secret name (e.g. "apiKey", "signingKey").
public type LoadedSecrets record {|
    map<string> secretValues;
|};
