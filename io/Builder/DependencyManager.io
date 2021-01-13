# The dependency manager for Builder

DependencyManager := Object clone do (

    package := nil

    headerSearchPaths := lazySlot(list(".", Eerie ioHeadersPath))

    libSearchPaths := lazySlot(list())

    _frameworkSearchPaths := lazySlot(list(
        "/System/Library/Frameworks",
        "/Library/Frameworks",
        "~/Library/Frameworks" stringByExpandingTilde))

    _searchPrefixes := lazySlot(list(
        System installPrefix,
        "/opt/local",
        "/usr",
        "/usr/local",
        "/usr/pkg",
        "/sw",
        "/usr/X11R6",
        "/mingw"))

    _headers := lazySlot(list())
    
    _libs := lazySlot(list())
    
    _frameworks := lazySlot(list())
    
    _syslibs := lazySlot(list())
    
    _linkOptions := lazySlot(list())

    init := method(
        self _searchPrefixes foreach(prefix,
            self appendHeaderSearchPath(prefix .. "/include"))

        self _searchPrefixes foreach(prefix, 
            self appendLibSearchPath(prefix .. "/lib")))

    with := method(pkg, 
        klone := self clone
        klone package := pkg
        klone)

    appendHeaderSearchPath := method(path, 
        dir := self _dirForPath(path)
        if(dir exists, 
            self headerSearchPaths appendIfAbsent(dir path)))

    appendLibSearchPath := method(path, 
        dir := self _dirForPath(path)
        if(dir exists,
            self libSearchPaths appendIfAbsent(dir path)))

    # returns directory relative to package's directory if the path is relative
    # or the directory with provided path if it's absolute
    _dirForPath := method(path,
        if (self _isPathAbsolute(path),
            Directory with(path),
            self package struct root directoryNamed(path)))

    # whether the path is absolute
    _isPathAbsolute := method(path,
        if (Eerie platform == "windows",
            path containsSeq(":\\") or path containsSeq(":/"),
            path beginsWithSeq("/")))

    dependsOnHeader := method(v, self _headers appendIfAbsent(v))

    dependsOnLib := method(v,
        if (self _libs contains(v), return)

        parentDir := File with(v) parentDirectory
        if (parentDir exists and parentDir path isEmpty not,
            self _searchPrefixes appendIfAbsent(parentDir path))

        pkgLibs := self _pkgConfigLibs(v)
        if(pkgLibs isEmpty,
            self _libs appendIfAbsent(v),
            pkgLibs map(l, self _libs appendIfAbsent(l)))

        self _pkgConfigCFlags(v) select(containsSeq("/")) foreach(p,
            self appendHeaderSearchPath(p)))

    _pkgConfigLibs := method(pkg,
        self _pkgConfig(pkg, "--libs") \
            splitNoEmpties(Builder DynamicLinkerCommand clone libFlag) \
                map(strip))

    _pkgConfig := method(pkg, flags,
        # this way we'll get empty lists for `_pkgConfigLibs` and
        # `_pkgConfigCFlags` methods if pkg-config isn't installed
        if (self _hasPkgConfig not, return "")

        date := Date now asNumber asHex
        resFile := self package struct build root path .. "/_pkg_config" .. date
        # System runCommand (System sh) doesn't allow pipes (?), 
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

    _hasPkgConfig := lazySlot(
        try (System sh("pkg-config --version", true)) isNil)

    _pkgConfigCFlags := method(pkg,
        self _pkgConfig(pkg, "--cflags") splitNoEmpties("-I") map(strip))

    dependsOnSysLib := method(v, self _syslibs appendIfAbsent(v))

    optionallyDependsOnLib := method(v, 
        a := self _pathForLib(v) != nil
        if(a, self dependsOnLib(v))
        a)

    _pathForLib := method(name,
        name containsSeq("/") ifTrue(return(name))
        libNames := list("." .. Eerie dllExt, ".a", ".lib") map(suffix, 
            "lib" .. name .. suffix)
        self libSearchPaths detect(path,
            libDirectory := Directory with(path)
            libNames detect(libName, libDirectory fileNamed(libName) exists)))

    dependsOnFramework := method(v, self _frameworks appendIfAbsent(v))

    optionallyDependsOnFramework := method(v, 
        a := self _pathForFramework(v) != nil
        if(a, self dependsOnFramework(v))
        a)

    _pathForFramework := method(name,
        frameworkname := name .. ".framework"
        self _frameworkSearchPaths detect(path,
            Directory with(path .. "/" .. frameworkname) exists))

    dependsOnFrameworkOrLib := method(v, w,
        path := self _pathForFramework(v)
        if(path != nil) then (
            self dependsOnFramework(v)
            self appendHeaderSearchPath(
                path .. "/" .. v .. ".framework/Headers")
        ) else (
            self dependsOnLib(w)))

    dependsOnLinkOption := method(v, 
        self _linkOptions appendIfAbsent(v))

    checkMissing := method(
        missing := self _missingHeaders
        if (missing isEmpty not,
            Exception raise(MissingHeadersError withArgs(missing)))

        missing := self _missingLibs
        if (missing isEmpty not,
            Exception raise(MissingLibsError withArgs(missing)))

        missing := self _missingFrameworks
        if (missing isEmpty not,
            Exception raise(MissingFrameworksError withArgs(missing))))

    _missingHeaders := method(
        self _headers select(h, self _pathForHeader(h) isNil))

    _pathForHeader := method(name,
        self headerSearchPaths detect(path,
            File with(path .. "/" .. name) exists))

    _missingLibs := method(self _libs select(p, self _pathForLib(p) isNil))

    _missingFrameworks := method(
        self _frameworks select(p, self _pathForFramework(p) isNil))

)

# error types
DependencyManager do (

    MissingHeadersError := Error clone setErrorMsg(
        """Header(s) #{call evalArgAt(0) join(", ")} not found.""")

    MissingLibsError := Error clone setErrorMsg(
        """Library(s) #{call evalArgAt(0) join(", ")} not found.""")

    MissingFrameworksError := Error clone setErrorMsg(
        """Framework(s) #{call evalArgAt(0) join(", ")} not found.""")

)
