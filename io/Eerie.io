//metadoc Eerie category API
//metadoc Eerie author Josip Lisec, Ales Tsurko
//metadoc Eerie description Eerie is the Io package manager.
SystemCommand

System userInterruptHandler := method(
    Eerie Transaction releaseLock
    super(userInterruptHandler))

Eerie := Object clone do(

    //doc Eerie isGlobal Whether the global environment in use. Default `false`.
    //doc Eerie setIsGlobal
    isGlobal ::= false
    
    init := method(
        # call this to check whether EERIEDIR set
        self root)

    //doc Eerie platform Get the platform name (`Sequence`) as lowercase.
    platform := System platform split at(0) asLowercase

    //doc Eerie ddlExt Get dynamic library extension for the current platform.
    dllExt := method(
        if (Eerie isWindows) then (
            return "dll"
        ) elseif (Eerie platform == "darwin") then (
            return "dylib"
        ) else (
            return "so"))

    /*doc Eerie isWindows Returns `true` if the OS on which Eerie is running is
    Windows (including mingw define), `false` otherwise.*/
    isWindows := method(System platform containsAnyCaseSeq("windows") or(
        System platform containsAnyCaseSeq("mingw")))

    //doc Eerie ioHeadersPath Returns path (`Sequence`) to io headers.
    ioHeadersPath := method(Eerie root .. "/ioheaders")

    //doc Eerie root Returns value of EERIEDIR environment variable.
    root := method(
        path := System getEnvironmentVariable("EERIEDIR") \
            ?stringByExpandingTilde
        if(path isNil or path isEmpty,
            Exception raise(EerieDirNotSetError with("")))
        path)

    /*doc Eerie sh(cmd[, dir=cwd])
    Executes system command. Raises exception with `Eerie SystemCommandError` on
    failure.*/
    sh := method(cmd, dir,
        self log(cmd, "console")
        prevDir := nil
        dirPrefix := ""
        if(dir != nil and dir != ".",
            dirPrefix = "cd " .. dir .. " && "
            prevDir = Directory currentWorkingDirectory
            Directory setCurrentWorkingDirectory(dir))

        cmdOut := System runCommand(dirPrefix .. cmd)
        stdOut := cmdOut stdout
        stdErr := cmdOut stderr

        prevDir isNil ifFalse(Directory setCurrentWorkingDirectory(prevDir))

        # System runCommand leaves weird files behind
        SystemCommand rmFilesContaining("-stdout")
        SystemCommand rmFilesContaining("-stderr")
        
        if(cmdOut exitStatus != 0,
            Exception raise(
                SystemCommandError with(cmd, cmdOut exitStatus, stdErr)))

        cmdOut exitStatus)

    _logMods := Map with(
        "info",         " - ",
        "error",        " ! ",
        "console",      " > ",
        "debug",        " # ",
        "install",      " + ",
        "transaction",  "-> ",
        "output",       "")

    /*doc Eerie log(message, mode) Displays the message to the user. Mode can be
    `"info"`, `"error"`, `"console"`, `"debug"` or `"output"`.*/
    log := method(str, mode,
        mode ifNil(mode = "info")
        stream := if (mode == "error", File standardError, File standardOutput)
        msg := ((self _logMods at(mode)) .. str) interpolate(call sender)
        stream write(msg, "\n"))

)

//doc Eerie Error Eerie modules subclass this error for their error types.
Eerie Error := Error clone do (
    errorMsg ::= nil

    with := method(msg,
        super(with(self errorMsg interpolate)))
)

Eerie do (
    //doc Eerie MissingPackageError
    MissingPackageError := Error clone setErrorMsg(
        "Package '#{call evalArgAt(0)}' is missing.")

    //doc Eerie SystemCommandError
    SystemCommandError := Error clone setErrorMsg(
        "Command '#{call evalArgAt(0)}' exited with status code " .. 
        "#{call evalArgAt(1)}:\n#{call evalArgAt(2)}")

    //doc Eerie EerieDirNotSetError
    EerieDirNotSetError := Error clone setErrorMsg(
        "Environment variable EERIEDIR did not set.")
)

Eerie clone = Eerie do (
    //doc Eerie Package [Package](package.html)
    doRelativeFile("Eerie/Package.io")
    //doc Eerie Downloader [Downloader](downloader.html)
    doRelativeFile("Eerie/Downloader.io")
    //doc Eerie Installer [Installer](installer.html)
    doRelativeFile("Eerie/Installer.io")
    //doc Eerie Transaction [Transaction](transaction.html)
    doRelativeFile("Eerie/Transaction.io")
    //doc Eerie Action [Action](action.html)
    doRelativeFile("Eerie/Action.io")

    init
)
