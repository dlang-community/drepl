/*
  Copyright: Martin Nowak 2013 -
  License: Subject to the terms of the MIT license, as written in the included LICENSE file.
  Authors: $(WEB code.dawg.eu, Martin Nowak)
*/
module dawg.drepl.interpreter;
import dawg.drepl.engines;
import std.algorithm, std.array, std.conv, std.string, std.typecons;

enum Result
{
    success,
    error,
    incomplete,
}

struct Interpreter(Engine) if (isEngine!Engine)
{
    Tuple!(Result, string) interpret(in char[] line)
    {
        // ignore empty lines on empty input
        if (!_incomplete.data.length && !line.length)
            return tuple(Result.success, "");

        _incomplete.put(line);
        _incomplete.put('\n');
        auto input = _incomplete.data;

        // dismiss buffer after two consecutive empty lines
        if (input.endsWith("\n\n\n"))
        {
            _incomplete.clear();
            return tuple(Result.error, "You typed two blank lines. Starting a new command.");
        }

        immutable kind = classify(input);
        Tuple!(EngineResult, string) res;
        final switch (kind)
        {
        case Kind.Decl:
            res = _engine.evalDecl(input);
            break;
        case Kind.Stmt:
            res = _engine.evalStmt(input);
            break;
        case Kind.Expr:
            res = _engine.evalExpr(input);
            break;

        case Kind.Incomplete:
            return tuple(Result.incomplete, "");

        case Kind.Error:
            _incomplete.clear();
            return tuple(Result.error, "Error parsing '"~input.strip.idup~"'.");
        }
        _incomplete.clear();
        return tuple(toResult(res[0]), res[1]);
    }

private:
    enum Kind { Decl, Stmt, Expr, Incomplete, Error, }

    import stdx.d.lexer, stdx.d.parser;

    Kind classify(in char[] input)
    {
        auto tokens = byToken(cast(ubyte[])input).array();

        auto tokenIds = tokens.map!(t => t.type)();
        if (!tokenIds.balancedParens(tok!"{", tok!"}") ||
            !tokenIds.balancedParens(tok!"(", tok!")") ||
            !tokenIds.balancedParens(tok!"[", tok!"]"))
            return Kind.Incomplete;

        import std.typetuple : TypeTuple;
        foreach (kind; TypeTuple!(Kind.Decl, Kind.Stmt, Kind.Expr))
            if (parse!kind(tokens))
                return kind;
        return Kind.Error;
    }

    bool parse(Kind kind)(in Token[] tokens)
    {
        scope parser = new Parser();
        static bool hasErr;
        hasErr = false;
        parser.fileName = "drepl";
        parser.setTokens(tokens);
        parser.messageFunction = (file, ln, col, msg, isErr) { if (isErr) hasErr = true; };
        static if (kind == Kind.Decl)
        {
            do
            {
                if (!parser.parseDeclaration()) return false;
            } while (parser.moreTokens());
        }
        else static if (kind == Kind.Stmt)
        {
            do
            {
                if (!parser.parseStatement()) return false;
            } while (parser.moreTokens());
        }
        else static if (kind == Kind.Expr)
        {
            if (!parser.parseExpression() || parser.moreTokens())
                return false;
        }
        return !hasErr;
    }

    unittest
    {
        auto intp = interpreter(echoEngine());
        assert(intp.classify("3+2") == Kind.Expr);
        // only single expressions
        assert(intp.classify("3+2 foo()") == Kind.Error);
        assert(intp.classify("3+2;") == Kind.Stmt);
        // multiple statements
        assert(intp.classify("3+2; foo();") == Kind.Stmt);
        assert(intp.classify("struct Foo {}") == Kind.Decl);
        // multiple declarations
        assert(intp.classify("void foo() {} void bar() {}") == Kind.Decl);
        // can't currently mix declarations and statements
        assert(intp.classify("void foo() {} foo();") == Kind.Error);
        // or declarations and expressions
        assert(intp.classify("void foo() {} foo()") == Kind.Error);
        // or statments and expressions
        assert(intp.classify("foo(); foo()") == Kind.Error);
    }

    static toResult(EngineResult er)
    {
        final switch (er)
        {
        case EngineResult.success: return Result.success;
        case EngineResult.error: return Result.error;
        }
    }

    Engine _engine;
    Appender!(const(char)[]) _incomplete;
}

Interpreter!Engine interpreter(Engine)(auto ref Engine e) if (isEngine!Engine)
{
    return Interpreter!Engine(move(e));
}

unittest
{
    auto intp = interpreter(echoEngine());
    assert(intp.interpret("3 * foo") == tuple(Result.success, "3 * foo"));
    assert(intp.interpret("stmt!(T)();") == tuple(Result.success, "stmt!(T)();"));
    assert(intp.interpret("auto a = 3 * foo;") == tuple(Result.success, "auto a = 3 * foo;"));

    void testMultiline(string input)
    {
        import std.string : splitLines;
        auto lines = splitLines(input);
        foreach (line; lines[0 .. $-1])
            assert(intp.interpret(line) == tuple(Result.incomplete, ""));
        assert(intp.interpret(lines[$-1]) == tuple(Result.success, input));
    }

    testMultiline(
        q{void foo() {
            }});

    testMultiline(
        q{int foo() {
                auto bar(int v) { return v; }
                auto v = 3 * 12;
                return bar(v);
            }});

    testMultiline(
        q{struct Foo(T) {
                void bar() {
                }
            }});

    testMultiline(
        q{struct Foo(T) {
                void bar() {

                }
            }});
}

unittest
{
    auto intp = interpreter(echoEngine());
    assert(intp.interpret("struct Foo {")[0] == Result.incomplete);
    assert(intp.interpret("")[0] == Result.incomplete);
    assert(intp.interpret("")[0] == Result.error);

    assert(intp.interpret("struct Foo {")[0] == Result.incomplete);
    assert(intp.interpret("")[0] == Result.incomplete);
    assert(intp.interpret("}")[0] == Result.success);
}
