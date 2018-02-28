/*
  Copyright: Martin Nowak 2013 -
  License: Subject to the terms of the MIT license, as written in the included LICENSE file.
  Authors: $(WEB code.dawg.eu, Martin Nowak)
*/
module drepl.engines.dmd;
import drepl.engines;
import std.algorithm, std.exception, std.file, std.path, std.process, std.range, std.stdio, std.string, std.typecons;

//------------------------------------------------------------------------------
// tmpfile et. al.

// should be in core.stdc.stdlib
version (Posix) extern(C) char* mkdtemp(char* template_);

string mkdtemp()
{
    version (Posix)
    {
        import core.stdc.string : strlen;
        auto tmp = buildPath(tempDir(), "drepl.XXXXXX\0").dup;
        auto dir = mkdtemp(tmp.ptr);
        return dir[0 .. strlen(dir)].idup;
    }
    else
    {
        import std.format, std.random;
        string path;
        do
        {
            path = buildPath(tempDir(), format("drepl.%06X\0", uniform(0, 0xFFFFFF)));
        } while (path.exists);
        return path;
    }
}

//------------------------------------------------------------------------------

DMDEngine dmdEngine()
{
    import core.sys.posix.unistd, std.random;
    auto compiler = environment.get("DMD", "dmd");
    auto tmpDir = mkdtemp();
    return DMDEngine(compiler, tmpDir);
}

struct DMDEngine
{
    string _compiler;
    string _tmpDir;
    size_t _id;

    @disable this(this);

    this(string compiler, string tmpDir)
    {
        _compiler = compiler;
        _tmpDir = tmpDir;
        if (_tmpDir.exists) rmdirRecurse(_tmpDir);
        mkdirRecurse(_tmpDir);
    }

    ~this()
    {
        if (_tmpDir) rmdirRecurse(_tmpDir);
    }

    EngineResult evalDecl(in char[] decl)
    {
        auto m = newModule();
        m.f.writefln(q{
            // for public imports
            public %1$s

            extern(C) void _decls()
            {
                import std.algorithm, std.stdio;
                writef("%%-(%%s, %%)", [__traits(allMembers, _mod%2$s)][1 .. $]
                       .filter!(d => !d.startsWith("_")));
            }
            }.outdent(), decl, _id);
        m.f.close();

        if (auto err = compileModule(m.path))
            return EngineResult(false, "", err);

        ++_id;

        auto func = cast(void function())loadFunc(m.path, "_decls");
        return captureOutput(func);
    }

    EngineResult evalExpr(in char[] expr)
    {
        auto m = newModule();
        m.f.writefln(q{
                extern(C) void _expr()
                {
                    import std.stdio;
                    static if (is(typeof((() => (%1$s))()) == void))
                        (%1$s), write("void");
                    else
                        write((%1$s));
                }
            }.outdent(), expr);
        m.f.close();

        if (auto err = compileModule(m.path))
            return EngineResult(false, "", err);

        ++_id;

        auto func = cast(void function())loadFunc(m.path, "_expr");
        return captureOutput(func);
    }

    EngineResult evalStmt(in char[] stmt)
    {
        auto m = newModule();
        m.f.writefln(q{
                extern(C) void _run()
                {
                    %s
                }
            }, stmt);
        m.f.close();

        if (auto err = compileModule(m.path))
            return EngineResult(false, "", err);

        ++_id;

        auto func = cast(void function())loadFunc(m.path, "_run");
        return captureOutput(func);
    }

private:
    EngineResult captureOutput(void function() dg)
    {
        // TODO: cleanup, error checking...
        import core.sys.posix.fcntl, core.sys.posix.unistd, std.conv : octal;

        .stdout.flush();
        .stderr.flush();
        immutable
            saveOut = dup(.stdout.fileno),
            saveErr = dup(.stderr.fileno),
            capOut = open(toStringz(_tmpDir~"/_stdout"), O_WRONLY|O_CREAT|O_TRUNC, octal!600),
            capErr = open(toStringz(_tmpDir~"/_stderr"), O_WRONLY|O_CREAT|O_TRUNC, octal!600);
        dup2(capOut, .stdout.fileno);
        dup2(capErr, .stderr.fileno);

        bool success = true;
        try
        {
            dg();
        }
        catch (Exception e)
        {
            success = false;
            stderr.writeln(e.toString());
        }
        .stdout.flush();
        .stderr.flush();
        close(.stdout.fileno);
        close(.stderr.fileno);
        dup2(saveOut, .stdout.fileno);
        dup2(saveErr, .stderr.fileno);
        close(saveOut);
        close(saveErr);
        return EngineResult(
            success, readText(_tmpDir~"/_stdout"), readText(_tmpDir~"/_stderr"));
    }

    Tuple!(File, "f", string, "path") newModule()
    {
        auto path = buildPath(_tmpDir, format("_mod%s", _id));
        auto f = File(path~".d", "w");
        writeHeader(f);
        return typeof(return)(f, path);
    }

    void writeHeader(ref File f)
    {
        if (_id > 0)
        {
            f.write("import _mod0");
            foreach (i; 1 .. _id)
                f.writef(", _mod%s", i);
            f.write(";");
        }
    }

    string compileModule(string path)
    {
        import std.regex;
        auto args = [_compiler, "-I"~_tmpDir, "-of"~path~".so", "-fPIC",
                     "-shared", path, "-L-l:libphobos2.so"];
        foreach (i; 0 .. _id)
            args ~= "-L"~_tmpDir~format("/_mod%s.so", i);
        auto dmd = execute(args);
        enum cleanErr = ctRegex!(`^.*Error: `, "m");
        if (dmd.status != 0)
            return dmd.output.replaceAll(cleanErr, "");
        if (!exists(path~".so"))
            return path~".so not found";
        return null;
    }

    void* loadFunc(string path, string name)
    {
        import core.runtime, core.demangle, core.sys.posix.dlfcn;

        auto lib = Runtime.loadLibrary(path~".so");
        if (lib is null)
        {
            auto msg = dlerror(); import core.stdc.string : strlen;
            throw new Exception("failed to load "~path~".so ("~msg[0 .. strlen(msg)].idup~")");
        }
        return dlsym(lib, toStringz(name));
    }
}

static assert(isEngine!DMDEngine);

unittest
{
    alias ER = EngineResult;

    DMDEngine dmd;

    dmd = dmdEngine();
    assert(dmd.evalExpr("5+2") == ER(true, "7"));
    assert(dmd.evalDecl("string foo() { return \"bar\"; }") == ER(true, "foo"));
    assert(dmd.evalExpr("foo()") == ER(true, "bar"));
    assert(!dmd.evalExpr("bar()").success);

    assert(dmd.evalDecl("struct Foo { }") == ER(true, "Foo"));
    assert(dmd.evalDecl("Foo f;") == ER(true, "f"));
    assert(dmd.evalStmt("f = Foo();") == ER(true, ""));

    dmd = dmdEngine();
    assert(dmd.evalDecl("void foo() {}") == ER(true, "foo"));
    assert(dmd.evalExpr("foo()") == ER(true, "void"));

    dmd = dmdEngine();
    assert(dmd.evalDecl("import std.stdio;").success);
    assert(dmd.evalStmt("writeln(\"foo\");") == ER(true, "foo\n"));
}

unittest
{
    alias ER = EngineResult;
    auto dmd = dmdEngine();
    assert(dmd.evalDecl("void foo(int) {}") == ER(true, "foo"));
    auto er = dmd.evalStmt("foo(\"foo\");");
    assert(!er.success);
    assert(er.stdout.empty);
    assert(!er.stderr.empty);
}
