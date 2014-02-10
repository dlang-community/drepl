/*
  Copyright: Martin Nowak 2013 -
  License: Subject to the terms of the MIT license, as written in the included LICENSE file.
  Authors: $(WEB code.dawg.eu, Martin Nowak)
*/
module dawg.drepl.engines;
public import dawg.drepl.engines.dmd, dawg.drepl.engines.echo;
import std.typecons;

enum EngineResult
{
    success,
    error,
}

template isEngine(Engine)
{
    enum isEngine =
        is(typeof(Engine.evalDecl("")) == Tuple!(EngineResult, string)) &&
        is(typeof(Engine.evalExpr("")) == Tuple!(EngineResult, string)) &&
        is(typeof(Engine.evalStmt("")) == Tuple!(EngineResult, string));
}
