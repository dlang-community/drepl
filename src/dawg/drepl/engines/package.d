/*
  Copyright: Martin Nowak 2013 -
  License: Subject to the terms of the MIT license, as written in the included LICENSE file.
  Authors: $(WEB code.dawg.eu, Martin Nowak)
*/
module dawg.drepl.engines;
public import dawg.drepl.engines.dmd, dawg.drepl.engines.echo;
import std.typecons;

struct EngineResult
{
    bool success;
    string stdout, stderr;
}

template isEngine(Engine)
{
    enum isEngine =
        is(typeof(Engine.evalDecl("")) == EngineResult) &&
        is(typeof(Engine.evalExpr("")) == EngineResult) &&
        is(typeof(Engine.evalStmt("")) == EngineResult);
}
