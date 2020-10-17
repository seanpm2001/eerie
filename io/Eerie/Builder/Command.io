# This module contains commands for compiler, static linker and dynamic linker

Command := Object clone do (
    asSeq := method(nil)
)

CompilerCommand := Command clone do (
    package := nil

    # the file this command should compile
    src ::= nil

    _depsManager := nil

    _defines := lazySlot(
        build := "BUILDING_#{self package name asUppercase}_ADDON" interpolate 
        
        result := if(Eerie platform == "windows",
            list(
                "WIN32",
                "NDEBUG", 
                "IOBINDINGS", 
                "_CRT_SECURE_NO_DEPRECATE"),
            list("SANE_POPEN",
                "IOBINDINGS"))

        if (list("cygwin", "mingw") contains(Eerie platform),
            result append(build))

        result)

    with := method(pkg, depsManager,
        klone := self clone
        klone package = pkg
        klone _depsManager = depsManager
        klone)

    addDefine := method(def, self _defines appendIfAbsent(def))

    asSeq := method(
        if (self src isNil, Exception raise(SrcNotSetError with("")))

        objName := self src name replaceSeq(".cpp", ".o") \
            replaceSeq(".c", ".o") \
                replaceSeq(".m", ".o")

        includes := self _depsManager _headerSearchPaths map(v, 
            "-I" .. v) join(" ")

        command := "#{self _cc} #{self _options} #{includes}" interpolate

        ("#{command} -c #{self _ccOutFlag}" ..
            "#{self package objsBuildDir path}/#{objName} " ..
            "#{self package sourceDir path}/#{self src name}") interpolate)

    _options := lazySlot(
        result := if(Eerie platform == "windows",
            "-MD -Zi",
            "-Os -g -Wall -pipe -fno-strict-aliasing -fPIC")

        cFlags := System getEnvironmentVariable("CFLAGS") ifNilEval("")
        
        result .. cFlags .. " " .. self _defines map(d, "-D" .. d) join(" "))
)

CompilerCommandWinExt := Object clone do (
    _cc := method(System getEnvironmentVariable("CC") ifNilEval("cl -nologo"))
    _ccOutFlag := "-Fo"
)

CompilerCommandUnixExt := Object clone do (
    _cc := method(System getEnvironmentVariable("CC") ifNilEval("cc"))
    _ccOutFlag := "-o "
)

if (Eerie platform == "windows", 
    CompilerCommand prependProto(CompilerCommandWinExt),
    CompilerCommand prependProto(CompilerCommandUnixExt)) 

# CompilerCommand error types
CompilerCommand do (
    SrcNotSetError := Eerie Error clone setErrorMsg(
        "Source file to compile doesn't set.")
)

StaticLinkerCommand := Command clone do (
    package := nil

    with := method(pkg,
        klone := self clone
        klone package = pkg
        klone)

    asSeq := method(
        path := self package dir path
        result := ("#{self _ar} #{self _arFlags}" ..
            "#{self package staticLibPath} " ..
            "#{self package objsBuildDir path}/*.o") interpolate

        if (self _ranlibSeq isEmpty, return result)
        
        result .. " && " .. self _ranlibSeq)

    _ranlibSeq := method(
        if (self _ranlib isNil, return "") 

        path := self package dir path
        "#{self _ranlib} #{self package staticLibPath}" interpolate)
)

StaticLinkerCommandWinExt := Object clone do (
    _ar := "link -lib -nologo"
    _arFlags := "-out:"
    _ranlib := nil
)

StaticLinkerCommandUnixExt := Object clone do (
    _ar := method(
        System getEnvironmentVariable("AR") ifNilEval("ar"))
    _arFlags := "rcu "

    _ranlib := method(
        System getEnvironmentVariable("RANLIB") ifNilEval("ranlib"))
)

if (Eerie platform == "windows",
    StaticLinkerCommand prependProto(StaticLinkerCommandWinExt),
    StaticLinkerCommand prependProto(StaticLinkerCommandUnixExt)) 

DynamicLinkerCommand := Command clone do (

    package := nil

    _depsManager := nil

    # this is for windows only
    manifestPath := method(self package dllPath .. ".manifest")

    with := method(pkg, depsManager,
        klone := self clone
        klone package = pkg
        klone _depsManager := depsManager
        klone)

    asSeq := method(
        links := self package installedPackages \
            select(hasNativeCode) \
                map(pkg, 
                    "#{self _dirPathFlag}#{pkg _dllBuildDir path}" interpolate)

        links appendSeq(self package installedPackages map(pkg,
            ("#{self _libFlag}" ..
                "#{self _nameWithLibSuffix(pkg dllName)}") interpolate))

        if(Eerie platform == "windows",
            links appendSeq(self _depsManager _syslibs map(v, v .. ".lib")))

        links appendSeq(
            self _depsManager _libSearchPaths map(v, 
                self _dirPathFlag .. v))

        links appendSeq(self _depsManager _libs map(v,
            if(v at(0) asCharacter == "-", 
                v,
                self _libFlag .. self _nameWithLibSuffix(v))))

        links appendSeq(list(self _dirPathFlag .. (System installPrefix), 
            self _libFlag .. self _nameWithLibSuffix("iovmall"),
            self _libFlag .. self _nameWithLibSuffix("basekit")))

        links appendSeq(
            self _depsManager _frameworks map(v, "-framework " .. v))

        links appendSeq(self _depsManager _linkOptions)

        s := ""

        if (Eerie platform == "darwin",
            links append("-flat_namespace")
            s := " -install_name " .. self package dllPath )

        linksJoined := links join(" ")

        cflags := System getEnvironmentVariable("CFLAGS") ifNilEval("")
        result := ("#{self _linkerCmd} #{cflags} #{self _dllCommand} #{s} " ..
            "#{self _outFlag}" ..
            "#{self package dllPath} " .. 
            "#{self package objsBuildDir path}/*.o #{linksJoined}") interpolate

        result .. "&&" .. self _embedManifestCmd)

    _dllCommand := method(
        if(Eerie platform == "darwin") then (
            return "-dynamiclib -single_module"
        ) elseif (Eerie platform == "windows") then (
            return "-dll -debug"
        ) else (
            return "-shared"))

    # get name of the library with lib suffix depending on platform
    _nameWithLibSuffix := method(name, name .. self _libSuffix)

    _embedManifestCmd := method(
        if((Eerie platform == "windows") not, return "")

        "mt.exe -manifest " .. self manifestPath ..
        " -outputresource:" .. self package dllPath)

)

DynamicLinkerCommandWinExt := Object clone do (
    _linkerCmd := "link -link -nologo"
    _dirPathFlag := "-libpath:"
    _libFlag := ""
    _libSuffix := ".lib"
    _outFlag := "-out:"
)

DynamicLinkerCommandUnixExt := Object clone do (
    _linkerCmd := method(
        _    System getEnvironmentVariable("CC") ifNilEval("cc"))
    _dirPathFlag := "-L"
    _libFlag := "-l"
    _libSuffix := ""
    _outFlag := "-o "
)

if (Eerie platform == "windows",
    DynamicLinkerCommand prependProto(DynamicLinkerCommandWinExt),
    DynamicLinkerCommand prependProto(DynamicLinkerCommandUnixExt)) 
