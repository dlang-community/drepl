
module dawg.drepl.parser;

import 
    std.stdio, 
    std.array,
    std.typecons;    

import 
    stdx.d.lexer, 
    stdx.d.parser, 
    stdx.d.ast;    

unittest
{
    auto parser = new ReplParser();
    auto atoms = parser.parse("auto a = 1;auto foo() { auto blah = 5; }writeln(`hi`);1+1;foreach(i; iota(10)) { writeln(i); }");
    assert(atoms[0] == Atom(AtomKind.Auto, "auto a = 1;"));
    assert(atoms[1] == Atom(AtomKind.Decl, "auto foo() { auto blah = 5; }"));
    assert(atoms[2] == Atom(AtomKind.Expr, "writeln(`hi`);"));
    assert(atoms[3] == Atom(AtomKind.Expr, "1+1;"));
    assert(atoms[4] == Atom(AtomKind.Stmt, "foreach(i; iota(10)) { writeln(i); }"));
    writeln("ReplParser: unittest succeeded");
}


enum AtomKind { Stmt, Decl, Expr, Auto }
alias Atom = Tuple!(AtomKind, "kind", string, "source");

class ReplParser : Parser
{
    Tuple!(size_t, size_t, string)[] errors;

    Atom[] parse(in char[] _source)
    {
        depth = 0;
        atoms.clear;
        errors.clear;
        source = _source.dup;

        // Reset parent state
        index = 0;
        suppressMessages = 0;
        LexerConfig config;
        StringCache* cache = new StringCache(StringCache.defaultBucketCount);
        tokens = byToken(cast(ubyte[]) source, config, cache).array();

        parseDeclarationsAndStatements();
        return atoms;
    } 
    
    override void error(lazy string message, bool shouldAdvance = true)
    {
        if (!suppressMessages)  
        {
            size_t column = index < tokens.length ? tokens[index].column : tokens[$ - 1].column;
            size_t line = index < tokens.length ? tokens[index].line : tokens[$ - 1].line;
            errors ~= tuple(line, column, message);
        }
        super.error(message, shouldAdvance);
    }    
               
    size_t charIndex()
    {        
        return index < tokens.length ? tokens[index].index : source.length;
    }
        
    override DeclarationOrStatement parseDeclarationOrStatement()
    {
        static size_t start = 0;

        if (!suppressMessages && !depth++)
            start = charIndex();

        auto r = super.parseDeclarationOrStatement();

        if (!suppressMessages && !--depth)
            atoms ~= Atom(kind, source[start..charIndex()]);

        return r;        
    }           
        
    override Declaration parseDeclaration()
    {
        switchKind(AtomKind.Decl);
        return super.parseDeclaration();                       
    }
        
    override Statement parseStatement()
    {
        switchKind(AtomKind.Stmt);
        return super.parseStatement();                       
    }
    
    override Expression parseExpression()
    {
        switchKind(AtomKind.Expr);
        return super.parseExpression();                       
    }    

    override AutoDeclaration parseAutoDeclaration()
    {
        switchKind(AtomKind.Auto);
        return super.parseAutoDeclaration();
    }

    static string makeBlocks()
    {
        enum blocks = [
            ["BlockStatement", "parseBlockStatement()"],
            ["StructBody", "parseStructBody()"],
            ["ForeachStatement", "parseForeachStatement()"],
            ["ForStatement", "parseForStatement()"],
            ["WhileStatement", "parseWhileStatement()"]
        ];

        string s;
        foreach(b; blocks)
            s ~= "override " ~ b[0] ~ " " ~ b[1] ~ "{ depth++; auto r = super." ~ b[1] ~ "; depth--; return r; }\n";
        return s;
    }

    mixin(ReplParser.makeBlocks());

private:

    int depth;
    AtomKind kind;
    Atom[] atoms;
    string source;

    void switchKind(AtomKind newKind)
    {
        if (!suppressMessages && depth == 1)
            kind = newKind;
    }

}
