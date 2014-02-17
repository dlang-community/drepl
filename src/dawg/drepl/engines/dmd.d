/*
  Copyright: Martin Nowak 2013 -
  License: Subject to the terms of the MIT license, as written in the included LICENSE file.
  Authors: $(WEB code.dawg.eu, Martin Nowak)
*/
module dawg.drepl.engines.dmd;
import dawg.drepl.engines;
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
    ProcessPipes _compiler;
    string _tmpDir;
    size_t _id;

    @disable this(this);

    this(string compiler, string tmpDir)
    {
        _tmpDir = tmpDir;
        sout = stdout;
        if (_tmpDir.exists) rmdirRecurse(_tmpDir);
        mkdirRecurse(_tmpDir);
        buildMod0();
    }

    ~this()
    {
        if (_tmpDir) rmdirRecurse(_tmpDir);
    }

    Tuple!(EngineResult, string) evalDecl(in char[] decl)
    {
        auto m = newModule();
        m.f.writefln(q{
            // for public imports
            public %1$s

            extern(C) string[] _decls()
            {
                return [__traits(allMembers, _mod%2$s)];
            }
            }.outdent(), decl, _id);
        m.f.close();

        if (auto err = compileModule(m.path))
            return error(err);

        ++_id;

        auto func = cast(string[] function())loadFunc(m.path, "_decls");
        try
            return success(func()[1 .. $].filter!(d => !d.startsWith("_")).join(", "));
        catch (Exception e)
            return error(e.toString());
    }

    Tuple!(EngineResult, string) evalExpr(in char[] expr)
    {
        auto m = newModule();
        m.f.writefln(q{
                extern(C) string _expr()
                {
                    return _toString(%1$s);
                }
            }.outdent(), expr);
        m.f.close();

        if (auto err = compileModule(m.path))
            return error(err);

        ++_id;

        auto func = cast(string function())loadFunc(m.path, "_expr");

        redirectStdout(); scope(failure) restoreStdout();

        try
        {
            auto res = func();
            return success(restoreStdout() ~ res);
        }
        catch (Exception e)
            return error(e.msg);
    }

    Tuple!(EngineResult, string) evalStmt(in char[] stmt)
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
            return error(err);

        ++_id;

        auto func = cast(void function())loadFunc(m.path, "_run");

        redirectStdout(); scope(failure) restoreStdout();

        try
            return func(), success(restoreStdout());
        catch (Exception e)
            return error(e.msg);
    }

private:

    File sout;

    void redirectStdout()
    {
        stdout = File(_tmpDir ~ "/_sout", "w");
    }

    string restoreStdout()
    {
        import std.file : readText;

        stdout.close();
        stdout = sout;
        return readText(_tmpDir ~ "/_sout");
    }


    void buildMod0()
    {
        auto mod = newModule();
        mod.f.writeln(q{
                string _toString(T)(auto ref T t)
                {
                    import std.conv : to;
                    return to!string(t);
                }

                string _toString(Args...)(auto ref Args args) if (Args.length > 1)
                {
                    string res = "tuple(";
                    foreach (i, a; args)
                    {
                        if (i) res ~= ", ";
                        res ~= _toString(a);
                    }
                    res ~= ")";
                    return res;
                }
        });
        if (auto err = compileModule(mod.path))
            throw new Exception(err);
        ++_id;
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
        auto args = ["dmd", "-I"~_tmpDir, "-of"~path~".so", "-fPIC",
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

    Tuple!(EngineResult, string) error(string msg)
    {
        return tuple(EngineResult.error, msg);
    }

    Tuple!(EngineResult, string) success(string msg)
    {
        return tuple(EngineResult.success, msg);
    }
}

static assert(isEngine!DMDEngine);
