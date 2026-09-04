import ballerina/http;

listener http:Listener statsHttpListener = new (statsServicePort);

// Exposes the watcher's running picture while it is watching the feed. Declared at module level so it starts
// as soon as the program runs and keeps serving requests alongside the watcher loop in `main`, rather than one
// blocking the other.
service /watcher on statsHttpListener {

    # Returns the running picture of what the watcher has seen so far: how many placements, updates and
    # removals, how many orders are sitting in each status right now, and when the last change came through.
    #
    # + return - the current running picture
    resource function get stats() returns WatcherStats {
        return watcherStats.snapshot();
    }
}
