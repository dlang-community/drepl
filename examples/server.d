import vibe.d;

shared static this()
{
    auto settings = new HTTPServerSettings;
    settings.port = 8080;
    settings.bindAddresses = ["::1", "127.0.0.1"];

    auto router = new URLRouter;
    router
        .get("/", &drepl)
        .get("*", serveStaticFiles("./public/"))
        .get("/ws/echo", handleWebSockets(&wsEcho))
        ;

    listenHTTP(settings, router);
}

void drepl(HTTPServerRequest req, HTTPServerResponse res)
{
    res.render!"drepl.dt"();
}

void wsEcho(WebSocket sock)
{
    while (sock.connected)
    {
        auto msg = sock.receiveText();
        logInfo(msg);
        sock.send(msg);
    }
}
