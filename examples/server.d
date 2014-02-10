import vibe.d, std.algorithm;

shared static this()
{
    auto settings = new HTTPServerSettings;
    settings.port = 8080;
    settings.bindAddresses = ["::1", "127.0.0.1"];
    if (getOption("bindAddress|bind", &settings.bindAddresses[0], "Sets the address used for serving."))
        settings.bindAddresses.length = 1;
    getOption("port|p", &settings.port, "Sets the port used for serving.");

    auto router = new URLRouter;
    router
        .get("/", &drepl)
        .get("*", serveStaticFiles("./public/"))
        .get("/ws/dmd", handleWebSockets(&runSession))
        ;

    logInfo("serving");
    listenHTTP(settings, router);
}

void drepl(HTTPServerRequest req, HTTPServerResponse res)
{
    res.render!"drepl.dt"();
}

void runSession(WebSocket sock)
{
    import std.process;
    auto p = pipeShell("sandbox -M ./drepl_sandbox");
    auto resp = Json.emptyObject;
    while (sock.connected)
    {
        auto msg = sock.receiveText();
        p.stdin.writeln(msg); p.stdin.flush();
        auto res = p.stdout.readln().findSplit(",");
        assert(res[1] == ",");

        resp.result = res[0];
        resp.text = res[2].htmlEscape();
        sock.send((scope stream) => writeJsonString(stream, resp));
    }
}
