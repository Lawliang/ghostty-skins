#if os(macOS)
import Testing
@testable import Ghostty

private typealias ParserSupport = MindControl.ParserSupport
private typealias ZigImports = MindControl.ZigImports
private typealias ScriptImports = MindControl.ScriptImports
private typealias PythonImports = MindControl.PythonImports
private typealias MarkdownLinks = MindControl.MarkdownLinks

struct ParserTests {
    @Test func joinResolvesDotsAndRejectsEscapes() {
        #expect(ParserSupport.join("src/app", "../core/x.zig") == "src/core/x.zig")
        #expect(ParserSupport.join("src", "./a/./b.ts") == "src/a/b.ts")
        #expect(ParserSupport.join("", "a.md") == "a.md")
        #expect(ParserSupport.join("src", "../../outside.zig") == nil)
        #expect(ParserSupport.directory(of: "a/b/c.zig") == "a/b")
        #expect(ParserSupport.directory(of: "c.zig").isEmpty)
    }

    @Test func zigImportsOnlyZigFiles() {
        let source = """
        const std = @import("std");
        const term = @import("terminal/main.zig");
        const x = @import( "../x.zig" );
        // const y = @import("ignored-but-harmless.zig");
        """
        #expect(ZigImports.specifiers(in: source) == ["terminal/main.zig", "../x.zig", "ignored-but-harmless.zig"])
    }

    @Test func scriptImportForms() {
        let source = """
        import React from 'react';
        import { a, b } from "./ab";
        import type { T } from '../types';
        import './side-effect';
        export * from './reexport';
        export { c } from "./c";
        const d = require('./d');
        const e = await import("./lazy");
        import {
          multi,
          line,
        } from './multi';
        """
        #expect(ScriptImports.specifiers(in: source) ==
                ["./ab", "../types", "./side-effect", "./reexport", "./c", "./d", "./lazy", "./multi"])
    }

    @Test func pythonImportForms() {
        let source = """
        import os, sys
        import pkg.sub.mod as m
        from pkg.util import helper, other as o
        from . import sibling
        from ..parent import thing
        from .local.mod import (x, y)
        """
        let imports = PythonImports.imports(in: source)
        #expect(imports.contains(.init(module: "os", names: [])))
        #expect(imports.contains(.init(module: "sys", names: [])))
        #expect(imports.contains(.init(module: "pkg.sub.mod", names: [])))
        #expect(imports.contains(.init(module: "pkg.util", names: ["helper", "other"])))
        #expect(imports.contains(.init(module: ".", names: ["sibling"])))
        #expect(imports.contains(.init(module: "..parent", names: ["thing"])))
        #expect(imports.contains(.init(module: ".local.mod", names: ["x", "y"])))
    }

    @Test func markdownLinkTargets() {
        let source = """
        See [the guide](docs/guide.md#setup) and ![diagram](img/arch.png "Arch").
        External [site](https://example.com), [anchor](#top), [mail](mailto:a@b.c).
        Spaces: [x](<my%20file.md>) and [y](../up.md?raw=1).
        """
        #expect(MarkdownLinks.targets(in: source) == ["docs/guide.md", "img/arch.png", "my file.md", "../up.md"])
    }
}
#endif
