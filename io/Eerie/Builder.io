//metadoc Builder category API
/*metadoc Builder description
Builder for native packages. This proto knows how to build a `Package` with
native code. 

Normally, you shouldn't use this directly. Use `Installer build` instead. But
here you'll find methods you can use inside your `build.io` script as it's
evaluated in the context of `Builder` (i.e. it's its ancestor).*/

Builder := Object clone do(
    //doc Builder platform Get the platform name (`Sequence`) as lowercase.
    platform := System platform split at(0) asLowercase

    /*doc Builder shouldGenerateInit Whether `Builder` should generate
    IoAddonNameInit.c file for your package. Default to `true`.*/
    shouldGenerateInit ::= true

    //doc Builder package Get the package the `Builder` will build.
    package := nil

    _cflags := method(System getEnvironmentVariable("CFLAGS") ifNilEval(""))

    _objsDir := lazySlot(self package dir createSubdirectory("_build/objs"))

    # see `InitFileGenerator`
    _initFileGenerator := nil

    //doc Builder with(Package) Always use this to initialize `Builder`.
    with := method(pkg, 
        klone := self clone
        klone package := pkg
        klone _initFileGenerator := InitFileGenerator with(pkg)
        klone)

    init := method(
        # TODO encapsulate into a proto (Depends?), move dependencies related
        # methods there as well
        self depends := Object clone do(
            headers := List clone
            libs := List clone
            frameworks := List clone
            syslibs := List clone
            includes := List clone
            linkOptions := List clone
            addons := List clone
        )

        self defines := List clone

        _setupPaths)

    _setupPaths := method(
        self frameworkSearchPaths := List clone
        frameworkSearchPaths append("/System/Library/Frameworks")
        frameworkSearchPaths append("/Library/Frameworks")
        frameworkSearchPaths append("/Local/Library/Frameworks")
        # frameworkSearchPaths append(
            # "~/Library/Frameworks" stringByExpandingTilde)

        self searchPrefixes := List clone

        searchPrefixes append(System installPrefix)
        searchPrefixes append("/opt/local")
        searchPrefixes append("/usr")
        if(platform != "darwin", searchPrefixes append("/usr/X11R6"))
        if(platform == "mingw", searchPrefixes append("/mingw"))
        searchPrefixes append("/usr/local")
        searchPrefixes append("/usr/pkg")
        searchPrefixes append("/sw")
        // on windows there is no such thing as a standard place
        // to look for these things
        searchPrefixes append("i:/io/addonLibs", "C:/io/addonLibs")

        self headerSearchPaths := List clone
        self appendHeaderSearchPath := method(v, 
            if(File clone setPath(v) exists,
                headerSearchPaths appendIfAbsent(v)))

        searchPrefixes foreach(searchPrefix,
            appendHeaderSearchPath(searchPrefix .. "/include"))

        if(platform == "windows" or platform == "mingw") then (
            appendHeaderSearchPath(
                Path with(System installPrefix, "include", "io") asIoPath)
        ) else (
            appendHeaderSearchPath(
                Path with(System installPrefix, "include", "io")))

        self libSearchPaths := List clone

        self appendLibSearchPath := method(v, 
            if(File clone setPath(v) exists, libSearchPaths appendIfAbsent(v)))

        if(platform == "windows" or platform == "mingw",
            self appendLibSearchPath(System installPrefix asIoPath))

        searchPrefixes foreach(searchPrefix, 
            appendLibSearchPath(searchPrefix .. "/lib")))

    addDefine := method(v, defines appendIfAbsent(v))
    dependsOnBinding := method(v, depends addons appendIfAbsent(v))
    dependsOnHeader := method(v, depends headers appendIfAbsent(v))
    dependsOnLib := method(v,
        depends libs contains(v) ifFalse(
            pkgLibs := pkgConfigLibs(v)
            if(pkgLibs isEmpty,
                depends libs appendIfAbsent(v),
                pkgLibs map(l, depends libs appendIfAbsent(l)))
            searchPrefixes appendIfAbsent(v)
            pkgConfigCFlags(v) select(containsSeq("/")) foreach(p,
                appendHeaderSearchPath(p))))

    pkgConfigLibs := method(pkg,
        pkgConfig(pkg, "--libs") splitNoEmpties(linkLibFlag) map(strip))
    pkgConfigCFlags := method(pkg,
        pkgConfig(pkg, "--cflags") splitNoEmpties("-I") map(strip))

    pkgConfig := method(pkg, flags,
        (platform == "windows") ifTrue(return(""))

        date := Date now asNumber asHex
        resFile := (self package dir path) .. "/_build/_pkg_config" .. date
        # System runCommand (Eerie sh) not allows pipes (?), 
        # so here we use System system instead
        statusCode := System system(
            "pkg-config #{pkg} #{flags} --silence-errors > #{resFile}" \
                interpolate)

        if(statusCode == 0) then (
            resFile := File with(resFile) openForReading
            flags := resFile contents asMutable strip
            resFile close remove
            return flags
        ) else (
            return ""))

    dependsOnFramework := method(v, depends frameworks appendIfAbsent(v))
    dependsOnInclude := method(v, depends includes appendIfAbsent(v))
    dependsOnLinkOption := method(v, depends linkOptions appendIfAbsent(v))
    dependsOnSysLib := method(v, depends syslibs appendIfAbsent(v))

    dependsOnFrameworkOrLib := method(v, w,
        path := pathForFramework(v)
        if(path != nil) then (
            dependsOnFramework(v)
            appendHeaderSearchPath(path .. "/" .. v .. ".framework/Headers")
        ) else (
            dependsOnLib(w)))

    pathForFramework := method(name,
        frameworkname := name .. ".framework"
        frameworkSearchPaths detect(path,
            Directory with(path .. "/" .. frameworkname) exists))

    optionallyDependsOnLib := method(v, 
        a := pathForLib(v) != nil
        if(a, dependsOnLib(v))
        a)

    pathForLib := method(name,
        name containsSeq("/") ifTrue(return(name))
        libNames := list("." .. _dllSuffix, ".a", ".lib") map(suffix, 
            "lib" .. name .. suffix)
        libSearchPaths detect(path,
            libDirectory := Directory with(path)
            libNames detect(libName, libDirectory fileNamed(libName) exists)))

    optionallyDependsOnFramework := method(v, 
        a := pathForFramework(v) != nil
        if(a, dependsOnFramework(v))
        a)

    hasDepends := method(
        (self missingFrameworks size + 
            self missingLibs size + 
            self missingHeaders size) == 0)

    missingFrameworks := method(
        missing := self depends frameworks select(p,
            self pathForFramework(p) == nil)

        if(missing contains(false),
            self isAvailable := false)

        missing)

    missingHeaders := method(
        missing := self depends headers select(h, self pathForHeader(p) == nil)
        if(missing contains(false),
            self isAvailable := false)

        missing)

    pathForHeader := method(name,
        headerSearchPaths detect(path,
            File with(path .. "/" .. name) exists))

    missingLibs := method(
        missing := self depends libs select(p, self pathForLib(p) == nil)
        if(missing contains(false),
            self isAvailable := false)

        missing)

    _systemCall := method(s,
        statusCode := Eerie sh(s, true)
        if(statusCode != 0, System exit(1))
        return statusCode)

    /*doc Builder build(options) Build the package with provided options 
    (`Sequence`).*/
    build := method(
        if (package hasNativeCode not, 
            Eerie log("The package #{self package name} has no code to compile")
            return)
    
        self _copyHeaders

        if (self shouldGenerateInit, self _initFileGenerator generate)

        # TODO defines should be preadded to `self defines`
        options := if(System platform split first asLowercase == "windows",
            "-MD -Zi -DWIN32 -DNDEBUG -DIOBINDINGS -D_CRT_SECURE_NO_DEPRECATE",
            "-Os -g -Wall -pipe -fno-strict-aliasing -DSANE_POPEN -DIOBINDINGS")
        options = options .. _cflags .. " " .. defines map(d,
            "-D" .. d) join(" ")

        self _cFiles foreach(src, self _compileFile(src, options))

        self _buildStaticLib
        self _buildDynLib
        self _embedManifest)

    # copy (install) headers into "_build/headers/"
    _copyHeaders := method(
        _mkdir("_build/headers")
        headers := self _headers

        if(headers size > 0,
            destinationPath := Path with(self package dir path, "_build/headers")
            headers foreach(file,
                file copyToPath(destinationPath .. "/" .. file name))))

    _mkdir := method(relativePath,
        path := Path with(self package dir path, relativePath)
        Directory with(path) createIfAbsent)

    # get list of headers
    _headers := method(
        Directory with(
            Path with(self package dir path, "source")) filesWithExtension(".h"))

    _cFiles := method(
        sourceFolder := self package sourceDir
        files := sourceFolder filesWithExtension("cpp") appendSeq(
            sourceFolder filesWithExtension("c"))
        if(platform != "windows", 
            files appendSeq(sourceFolder filesWithExtension("m")))
        files select(f, f name beginsWithSeq("._") not))

    _compileFile := method(src, options,
        Eerie log("Compiling #{src name}")
        obj := src name replaceSeq(".cpp", ".o") replaceSeq(".c", ".o") \
            replaceSeq(".m", ".o")

        objFile := self _objsDir fileNamed(obj)

        if(objFile exists not or(
            objFile lastDataChangeDate < src lastDataChangeDate),
            includes := self includePaths
            includes = includes appendSeq(headerSearchPaths) map(v, "-I" .. v)

            _depends := self depends includes join(" ")

            _includes := includes join(" ")

            command := "#{cc} #{options} #{_depends} #{_includes} -I." \
                interpolate

            if(list("cygwin", "mingw", "windows") contains(platform) not,
                command = command .. " -fPIC "
                ,
                command = command .. \
                    " -DBUILDING_#{self package name asUppercase}_ADDON " \
                        interpolate)

            command = "#{command} -c #{ccOutFlag}#{self package dir path}/_build/objs/#{obj} #{self package dir path}/source/#{src name}" interpolate
            _systemCall(command)))

    includePaths := method(
        # TODO what is it? Is this `package dir `/libs or `package
        # dir`/_build/libs?
        # given the logic of `_objsDir` it's the former
        libsFolder := Directory with("libs")
        includePaths := List clone
        if(libsFolder exists,
            includePaths appendSeq(
                libsFolder directories map(path) map(p, 
                    Path with(p, "_build/headers"))))

        # TODO commented this block, it looks like it's not needed anymore, but
        # let it be here until the refactoring
        # includePaths appendSeq(
            # depends addons map(n, 
                # (Eerie usedEnv path) .. "/addons/" .. n .. "/_build/headers"))
        includePaths)


    _buildStaticLib := method(
        staticLibName := "libIo" .. self package name ..  ".a"

        Eerie log("Building #{staticLibName}")
        
        _mkdir("_build/lib")
        path := self package dir path
        _systemCall("#{ar} #{arFlags}#{path}/_build/lib/#{staticLibName} #{path}/_build/objs/*.o" \
            interpolate)
        if(ranlib != nil,
            _systemCall("#{ranlib} #{path}/_build/lib/#{staticLibName}" interpolate)))

    _dllCommand := method(
        if(platform == "darwin",
            "-dynamiclib -single_module"
            ,
            if (platform == "windows",
                "-dll -debug"
                ,
                "-shared")))

    _buildDynLib := method(
        libname := dllNameFor("Io" .. self package name)

        Eerie log("Building #{libname}")

        _mkdir("_build/dll")

        # FIXME this should be `package dir with("_addons")` and `_build/dll`
        # inside of those addons. But the path, most probably, should be
        # absolute or better it should be relative to `package dir`
        links := depends addons map(b, 
            "#{linkDirPathFlag}../#{b}/_build/dll" interpolate)

        links appendSeq(depends addons map(v,
            "#{self linkLibFlag}Io#{v}#{self linkLibSuffix}" interpolate))

        if(platform == "windows",
            links appendSeq(depends syslibs map(v, v .. ".lib")))

        if(platform != "darwin" and platform != "windows",
            links appendSeq(
                depends addons map(v,
                    # TODO
                    "-Wl,--rpath -Wl,#{Eerie root}/activeEnv/addons/#{v}/_build/dll/" interpolate)))

        links appendSeq(libSearchPaths map(v, linkDirPathFlag .. v))

        links appendSeq(depends libs map(v,
            if(v at(0) asCharacter == "-", 
                v,
                linkLibFlag .. v .. linkLibSuffix)))

        links appendSeq(list(linkDirPathFlag .. (System installPrefix), 
            linkLibFlag .. "iovmall" .. linkLibSuffix,
            linkLibFlag .. "basekit" .. linkLibSuffix))

        links appendSeq(depends frameworks map(v, "-framework " .. v))

        links appendSeq(depends linkOptions)

        s := ""

        if(platform == "darwin",
            links append("-flat_namespace")
            # FIXME Eerie root /activeEnv/addons There's no such thing anymore
            s := " -install_name " .. (Eerie root) .. "/activeEnv/addons/" .. self package name .. "/_build/dll/" .. libname)

        linksJoined := links join(" ")

        linkCommand := "#{linkdll} #{_cflags} #{_dllCommand} #{s} #{linkOutFlag}#{self package dir path}/_build/dll/#{libname} #{self package dir path}/_build/objs/*.o #{linksJoined}" interpolate
        _systemCall(linkCommand))

    dllNameFor := method(s, "lib" .. s .. "." .. _dllSuffix)

    _dllSuffix := method(
        if(list("cygwin", "mingw", "windows") contains(platform), return "dll")
        if(platform == "darwin", return "dylib")
        "so")

    _embedManifest := method(
        if((platform == "windows") not, return)
        dllFilePath := self package dir path .. "/_build/dll/" .. dllNameFor("Io" .. self package name)
        manifestFilePath := dllFilePath .. ".manifest"
        _systemCall("mt.exe -manifest " .. manifestFilePath .. \
            " -outputresource:" .. dllFilePath)
        Eerie log("Removing manifest file #{manifestFilePath}")
        File with(self package dir path .. "/" .. manifestFilePath) remove)
)

InitFileGenerator := Object clone do (
    package ::= nil

    # the initializer
    with := method(pkg, self clone setPackage(pkg))

    # io files inside inside `io` directory
    # FIXME this should be `recursiveFileOfTypes(list("io"))`, but the generated
    # code may need to be changed too
    ioFiles := method(self ioCodeFolder filesWithExtension("io"))
    
    # directory with Io code
    ioCodeFolder := method(self package dir directoryNamed("io"))
    
    # path to the generated file (`Sequence`)
    path := method("source/Io" .. self package name .. "Init.c")

    # whether the compiled package should embed io code into the library
    embedIoCode ::= false

    # generates the file
    generate := method(
        Eerie log("Generating #{path}")
        initFile := self package dir fileNamed(path) remove create open
        initFile write("#include \"IoState.h\"\n")
        initFile write("#include \"IoObject.h\"\n\n")

        sourceFiles := self package dir directoryNamed("source") files
        iocFiles := sourceFiles select(f, f name beginsWithSeq("Io") and(f name endsWithSeq(".c")) and(f name containsSeq("Init") not) and(f name containsSeq("_") not))
        iocppFiles := sourceFiles select(f, f name beginsWithSeq("Io") and(f name endsWithSeq(".cpp")) and(f name containsSeq("Init") not) and(f name containsSeq("_") not))

        iocFiles appendSeq(iocppFiles)
        extraFiles := sourceFiles select(f, f name beginsWithSeq("Io") and(f name endsWithSeq(".c")) and(f name containsSeq("Init") not) and(f name containsSeq("_")))

        orderedFiles := List clone appendSeq(iocFiles)

        iocFiles foreach(f,
            d := f open readLines detect(line, line containsSeq("docDependsOn"))
            f close

            if(d,
                prerequisitName := "Io" .. d afterSeq("(\"") beforeSeq("\")") .. ".c"
                prerequisit := orderedFiles detect(of, of name == prerequisitName )
                orderedFiles remove(f)
                orderedFiles insertAfter(f, prerequisit)))

        iocFiles = orderedFiles

        iocFiles foreach(f,
            initFile write("IoObject *" .. f name fileName .. "_proto(void *state);\n"))

        extraFiles foreach(f,
            initFile write("void " .. f name fileName .. "Init(void *context);\n"))

        if (Builder platform == "windows",
            initFile write("__declspec(dllexport)\n"))

        initFile write("\nvoid " .. path fileName .. "(IoObject *context)\n")

        initFile write("{\n")

        if(iocFiles size > 0,
            initFile write("\tIoState *self = IoObject_state((IoObject *)context);\n\n"))

        iocFiles foreach(f,
            initFile write("\tIoObject_setSlot_to_(context, SIOSYMBOL(\"" .. f name fileName asMutable removePrefix("Io") .. "\"), " .. f name fileName .. "_proto(self));\n\n"))

        extraFiles foreach(f,
            initFile write("\t" .. f name fileName .. "Init(context);\n"))

        if(ioCodeFolder and self embedIoCode,
            ioFiles foreach(f, initFile write(codeForIoFile(f))))

        initFile write("}\n")
        initFile close)

    codeForIoFile := method(f,
        code := Sequence clone
        if (f size > 0,
            code appendSeq("\t{\n\t\tchar *s = ")
            code appendSeq(f contents splitNoEmpties("\n") map(line,
                "\"" .. line escape .. "\\n\"") join("\n\t\t"))
            code appendSeq(";\n\t\tIoState_on_doCString_withLabel_(self, context, s, \"" .. f name .. "\");\n")
            code appendSeq("\t}\n\n"))
        code)
)

BuilderWindows := Object clone do (
    ccOutFlag := "-Fo"
    linkdll := "link -link -nologo"
    linkDirPathFlag := "-libpath:"
    linkLibFlag := ""
    linkOutFlag := "-out:"
    linkLibSuffix := ".lib"
    ar := "link -lib -nologo"
    arFlags := "-out:"
    ranlib := nil

    cc := method(
        System getEnvironmentVariable("CC") ifNilEval("cl -nologo"))

    cxx := method(
        System getEnvironmentVariable("CXX") ifNilEval("cl -nologo"))
)

BuilderUnix := Object clone do (
    cc := method(
        System getEnvironmentVariable("CC") ifNilEval("cc"))

    cxx := method(
        System getEnvironmentVariable("CXX") ifNilEval("g++"))

    ccOutFlag := "-o "
    linkdll := cc
    linkDirPathFlag := "-L"
    linkLibFlag := "-l"
    linkLibSuffix := ""
    linkOutFlag := "-o "
    linkLibSuffix := ""

    ar := method(
        System getEnvironmentVariable("AR") ifNilEval("ar"))
    arFlags := "rcu "

    ranlib := method(
        System getEnvironmentVariable("RANLIB") ifNilEval("ranlib"))
)

if (Builder platform == "windows",
    Builder prependProto(BuilderWindows),
    Builder prependProto(BuilderUnix)) 
