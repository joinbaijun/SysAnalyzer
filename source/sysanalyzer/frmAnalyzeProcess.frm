VERSION 5.00
Object = "{831FDD16-0C5C-11D2-A9FC-0000F8754DA1}#2.0#0"; "mscomctl.ocx"
Begin VB.Form frmAnalyzeProcess 
   Caption         =   "Analyze Process"
   ClientHeight    =   4380
   ClientLeft      =   60
   ClientTop       =   345
   ClientWidth     =   10065
   LinkTopic       =   "Form1"
   ScaleHeight     =   4380
   ScaleWidth      =   10065
   StartUpPosition =   2  'CenterScreen
   Begin VB.Frame fraPB 
      BorderStyle     =   0  'None
      Height          =   615
      Left            =   0
      TabIndex        =   1
      Top             =   3780
      Width           =   9915
      Begin VB.CommandButton cmdAbort 
         Caption         =   "Abort"
         Height          =   540
         Left            =   9000
         TabIndex        =   4
         Top             =   0
         Visible         =   0   'False
         Width           =   855
      End
      Begin MSComctlLib.ProgressBar pb 
         Height          =   255
         Left            =   0
         TabIndex        =   2
         Top             =   0
         Width           =   8895
         _ExtentX        =   15690
         _ExtentY        =   450
         _Version        =   393216
         Appearance      =   1
      End
      Begin MSComctlLib.ProgressBar pb2 
         Height          =   255
         Left            =   0
         TabIndex        =   3
         Top             =   300
         Width           =   8895
         _ExtentX        =   15690
         _ExtentY        =   450
         _Version        =   393216
         Appearance      =   1
      End
   End
   Begin VB.ListBox List1 
      BeginProperty Font 
         Name            =   "Courier New"
         Size            =   11.25
         Charset         =   0
         Weight          =   400
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      Height          =   3630
      Left            =   0
      TabIndex        =   0
      Top             =   60
      Width           =   9975
   End
End
Attribute VB_Name = "frmAnalyzeProcess"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'AnalyzeProcess now x64 safe in dump routines..oops 9.8.16

Dim proc As New CProcessInfo
Dim qdf As New CDumpFix
Dim cst As New CStrings
'Dim scanner As New CExploitScanner 'these signatures are to old to use anymore, engine is ok though if we update sigs..

Dim rep()
Dim Base As String
Public samplePath As String
Dim pFolder As String
Dim abort As Boolean

Public Function ClearList()
    List1.Clear
End Function

Public Function AnalyzeKnownProcessesforRWE(csvProcessList As String)
    
    Dim c As Collection
    Dim tmp() As String
    Dim pName
    Dim cp As CProcess
    Dim exeBaseName As String
    
    Set c = proc.GetRunningProcesses()
    AddLine "Scanning Known Processes for RWE Memory injections: " & csvProcessList
    
    pFolder = UserDeskTopFolder & "\RWE_Memory"
    If Not fso.FolderExists(pFolder) Then MkDir pFolder
    
    tmp = Split(csvProcessList, ",")
    For Each cp In c
        For Each pName In tmp
            If Len(pName) > 0 Then
                If InStr(1, cp.path, pName, vbTextCompare) > 0 Then
                    exeBaseName = fso.GetBaseName(cp.path)
                    AddLine "Scanning pid:" & cp.pid & " " & cp.path
                    ScanForRWE cp.pid, exeBaseName & "_"
                End If
            End If
        Next
    Next
    
    debugLog "RWE Memory Scan Report:" & vbCrLf & GetReport()
    
    Dim f() As String
    f() = fso.GetFolderFiles(pFolder)
    If AryIsEmpty(f) Then
        fso.DeleteFolder pFolder, True
    End If
    
End Function

Public Function GetReport() As String

    Dim report As String
    Dim al() As String
    
    For i = 0 To List1.ListCount - 1
        push al(), List1.list(i)
    Next
        
    GetReport = Join(al, vbCrLf)
     
End Function

Private Function AddLine(msg As String)
    List1.AddItem msg
    List1.ListIndex = List1.ListCount - 1
    Me.Refresh
    DoEvents
End Function
    

Public Function AnalyzeProcess(pid As Long) ', Optional memoryMapOnly As Boolean = False)
    
    On Error Resume Next
    
    Erase rep()
    
    Dim pth As String
    Dim cmod As CModule
    Dim col As Collection
    Dim f As String
    Dim report As String
    Dim mm As matchModes
    
    pb.max = 6
    Me.Visible = True
    f = proc.GetProcessPath(pid)
    Base = fso.GetBaseName(f)
    samplePath = Base
    
    debugLog "AnalyzeProcess pid:" & pid & " " & f
    
    pFolder = UserDeskTopFolder & "\" & Base
    If Not fso.FolderExists(pFolder) Then MkDir pFolder
    
     
    FileCopy f, pFolder & "\" & Base & "_sample.exe_"
    pth = pFolder & "\" & Base & "_dmp.exe_"
     
    AddLine "Compiling base file statistics for " & f
    
    push rep, "File: " & fso.FileNameFromPath(f)
    push rep, "Size: " & FileLen(f) & " Bytes"
    push rep, "MD5: " & hash.HashFile(f)
    'push rep, "Packer: " & GetPacker(f) & vbCrLf 'peid databases are to old now..
    'push rep, "File Properties: " & QuickInfo(f) & vbCrLf
    
        
    pb.value = pb.value + 1
    AddLine "Enumerating loaded dlls.."
    
    Set col = proc.GetProcessModules(pid)
    
    If known.Loaded And known.Ready Then
        'ado.OpenConnection
        push rep, "Unknown Loaded Modules: (using known database)" & vbCrLf & String(75, "-")
    Else
        push rep, "All Loaded Modules: " & vbCrLf & String(75, "-")
    End If
    
    Dim dllName As String
    Dim i As Long
        
    For Each cmod In col
    
        If known.Loaded And known.Ready Then
            If i = 0 And Right(cmod.path, 3) = "exe" Then
                DoEvents 'we already took a memory dump of the main exe..
            Else
                If known.isFileKnown(cmod.path) <> exact_match Then
                    AddLine "Unknown or Changed Dll Dumping: " & cmod.HexBase & ": " & cmod.path
                    push rep, "Dumping: " & cmod.HexBase & vbTab & cmod.path
                    dllName = fso.FileNameFromPath(cmod.path)
                    If Len(dllName) = 0 Then dllName = cmod.HexBase & ".dll"
                    dllName = pFolder & "\" & dllName & ".dmp"
                    If proc.DumpMemory(pid, cmod.HexBase, cmod.HexSize, dllName) Then  'now x64 safe 9.8.16 oops
                        qdf.QuickDumpFix dllName
                        AddLine "Doing String dump.."
                        doStringDump fso.GetBaseName(dllName), dllName
                    Else
                        AddLine "FAILED to dump " & dllName & " x64: " & cmod.isx64 & " pid: " & pid & " Base: " & cmod.HexBase & " size: " & cmod.HexSize
                    End If
                End If
            End If
        Else
            'push rep, Hex(cmod.Base) & vbTab & cmod.path
        End If
        
        i = i + 1
    Next
    
    'If known.Loaded And known.Ready Then ado.CloseConnection
    
    pb.value = pb.value + 1
    
    AddLine "Dumping main process memory"
    Set cmod = col(1)
    Call proc.DumpMemory(pid, cmod.HexBase, cmod.HexSize, pth)
    pb.value = pb.value + 1

    If Not fso.FileExists(pth) Then
        AddLine "Memory dump failed, file not found."
    Else
        AddLine "Processing memory dump"
        
        'push rep, "Exploit Signatures:"
        'push rep, String(75, "-")
        'push rep, Join(ExploitScanner(pth), vbCrLf)
    
        qdf.QuickDumpFix pth
        doStringDump Base, pth
    End If
    
    pb.value = pb.value + 1
    AddLine "Scanning for RWE memory sections.."
    ScanForRWE pid

    pb.value = 0
    'report = pFolder & "\" & Base & "_report.txt"
    'fso.writeFile report, Join(rep, vbCrLf)
    'AddLine  "Process Analysis Complete saving report as: " & Replace(report, UserDeskTopFolder, Empty)
    'AddLine String(75, "-")
    
    AddLine "Process Analysis Complete"
    debugLog "Process Analysis Log:" & vbCrLf & Join(rep, vbCrLf) & GetReport()
    List1.Clear
    
End Function


Private Sub doStringDump(ByVal baseFileName As String, dmpPath As String)
    
    On Error Resume Next
    
    Dim pth2 As String
    Dim rawStrings As String
    Dim config() As String
    Dim tmp() As String
    Dim buf() As String
    Dim extracts() As String
    
    If InStr(baseFileName, ".") > 0 Then baseFileName = fso.GetBaseName(baseFileName)
    
    rawStrings = cst.ExtractStrings(dmpPath)
    buf = Split(rawStrings, vbCrLf)
    
    ' format is comma delimited entries, first entry is section name for report
    ' all other entries are string to find for this section
    push config(), "Urls,http:,ftp:"
    push config(), "RegKeys,software" ', CurrentControl, clsid"
    push config(), "ExeRefs,.exe"

    For j = 0 To UBound(config)
        c = config(j)
        c = Trim(c)
        If Len(c) = 0 Then GoTo nextone
         
        tmp = Split(c, ",")
        If AryIsEmpty(tmp) Then GoTo nextone
    
        If UBound(tmp) = 0 Then
            push rep, "bad format for grep criteria"
        Else
            x = Empty
            For i = 1 To UBound(tmp)
                x = x & cst.LineGrep(buf, tmp(i))
            Next
            If Len(x) > 0 Then
                push extracts, tmp(0)
                push extracts, String(50, "-")
                push extracts, x
                push extracts, Empty
            End If
        End If
nextone:
        DoEvents
    Next
    
    push extracts, "Raw Strings: (" & cst.FilteredCount & " lines filtered out)"
    push extracts, String(50, "-")
    push extracts, rawStrings
    
    pth2 = pFolder & "\" & baseFileName & "_strings.log"
    fso.writeFile pth2, Join(extracts, vbCrLf)
    
End Sub

Private Sub ScanForRWE(pid As Long, Optional prefix As String = "") 'not x64 compatiabled...
    
    Dim c As Collection
    Dim cMem As CMemory
    Dim dmpPath As String
    
    On Error Resume Next
    
    AddLine "Loading memory map for pid: " & pid & " Path: " & proc.GetProcessPath(pid)
    
    'If proc.x64.IsProcess_x64(pid) <> r_32bit Then
    '    AddLine "Can only load memory map for 32bit processes"
    '    Exit Sub
    'End If
    
    Set c = proc.GetMemoryMap(pid)
    
    If c.count = 0 Then
        AddLine "Failed to load memory map!"
        Exit Sub
    End If
    
    pb2.value = 0
    pb2.max = c.count
    
    Dim s As String
    Dim entropy As Integer
    
    abort = False
    cmdAbort.Visible = True
    cmdAbort.Refresh
    Me.Refresh
    DoEvents
    DoEvents
    DoEvents
    
    For Each cMem In c
                    
        If abort Then
            AddLine "User aborted scanning memory map!"
            Exit For
        End If
        
        If cMem.Protection = PAGE_EXECUTE_READWRITE And cMem.MemType <> MEM_IMAGE Then
        
            If VBA.Left(proc.ReadMemory(cMem.pid, cMem.Base, 2), 2) = "MZ" Then
                AddLine pHex(cMem.Base) & " is RWE but not part of an image (CONFIRMED INJECTION) dumping..."
                push rep, List1.list(List1.ListCount - 1)
                dmpPath = DumpMemorySection(pid, cMem, prefix)
                If fso.FileExists(dmpPath) Then
                    AddLine "Doing a quick dump fix on " & dmpPath
                    push rep, List1.list(List1.ListCount - 1)
                    qdf.QuickDumpFix dmpPath
                End If
            Else
                If cMem.size < &H10000 Then
                    s = proc.ReadMemory(cMem.pid, cMem.Base, cMem.size) 'doesnt add that much time (if small)
                    entropy = CalculateEntropy(s) 'helps eliminate noise
                    If entropy > 40 Then
                        AddLine pHex(cMem.Base) & " is RWE but not part of an image..possible injection entropy: " & entropy & "%  size:" & Hex(cMem.size)
                        dmpPath = DumpMemorySection(pid, cMem, "raw_" & prefix)
                        If fso.FileExists(dmpPath) Then AddLine "Memory dump saved as " & dmpPath
                        push rep, List1.list(List1.ListCount - 1)
                    End If
                Else
                    'notable for its size..
                    AddLine pHex(cMem.Base) & " is LARGE RWE (" & pHex(cMem.size) & ") but not part of an image dumping..."
                    push rep, List1.list(List1.ListCount - 1)
                    dmpPath = DumpMemorySection(pid, cMem, prefix)
                    If fso.FileExists(dmpPath) Then AddLine "Memory dump saved as " & dmpPath
                End If
            End If
         
        End If
         
        pb2.value = pb2.value + 1
        pb2.Refresh
        Me.Refresh
        DoEvents
        
    Next
        
    pb2.value = 0
    cmdAbort.Visible = False
    
End Sub

Private Function DumpMemorySection(pid As Long, cMem As CMemory, Optional prefix As String = "") As String

    On Error Resume Next
    Dim dmpPath As String

    dmpPath = pFolder & "\" & prefix & pHex(cMem.Base) & ".mem"
    
    If proc.DumpProcessMemory(pid, cMem.Base, cMem.size, dmpPath) Then
        AddLine "Memory dump of injection successfully saved"
        AddLine "Doing string dump of memory section.."
        doStringDump Hex(cMem.Base), dmpPath
        DumpMemorySection = dmpPath
    Else
        AddLine "Error saving memory dump: " & Err.Description
    End If
    
End Function

Private Sub cmdAbort_Click()
    abort = True
End Sub

Private Sub Form_Load()
    On Error Resume Next
    Me.Icon = frmMain.Icon
    RestoreFormSizeAnPosition Me
    AlwaysOnTop Me
End Sub

Private Sub Form_Resize()
    On Error Resume Next
    List1.Height = Me.Height - List1.Top - fraPB.Height - 400
    fraPB.Top = Me.Height - fraPB.Height - 400
    List1.Width = Me.Width - List1.Left - 200
    fraPB.Width = Me.Width - fraPB.Left - 200
    cmdAbort.Left = fraPB.Width - cmdAbort.Width - 200
    pb.Width = cmdAbort.Left - 200
    pb2.Width = pb.Width
End Sub

Private Sub Form_Unload(Cancel As Integer)
    SaveFormSizeAnPosition Me
End Sub
