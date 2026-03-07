type
  Sqlite3Obj {.importc: "sqlite3", header: "sqlite3.h", incompleteStruct.} = object
  Sqlite3StmtObj {.importc: "sqlite3_stmt", header: "sqlite3.h", incompleteStruct.} = object

  Sqlite3Destructor* = proc(value: pointer) {.cdecl.}
  Sqlite3* = ptr Sqlite3Obj
  Sqlite3Stmt* = ptr Sqlite3StmtObj

const
  SQLITE_OK* = 0.cint
  SQLITE_ERROR* = 1.cint
  SQLITE_ROW* = 100.cint
  SQLITE_DONE* = 101.cint
  SQLITE_INTEGER* = 1.cint
  SQLITE_FLOAT* = 2.cint
  SQLITE_TEXT* = 3.cint
  SQLITE_BLOB* = 4.cint
  SQLITE_NULL* = 5.cint

proc sqlite3_open*(filename: cstring; db: var Sqlite3): cint {.cdecl, importc,
    header: "sqlite3.h".}
proc sqlite3_close_v2*(db: Sqlite3): cint {.cdecl, importc, header: "sqlite3.h".}
proc sqlite3_errmsg*(db: Sqlite3): cstring {.cdecl, importc, header: "sqlite3.h".}
proc sqlite3_exec*(db: Sqlite3; sql: cstring; callback: pointer; arg: pointer;
    errMsg: ptr cstring): cint {.cdecl, importc, header: "sqlite3.h".}
proc sqlite3_free*(value: pointer) {.cdecl, importc, header: "sqlite3.h".}
proc sqlite3_enable_load_extension*(db: Sqlite3; onoff: cint): cint {.cdecl, importc,
    header: "sqlite3.h".}
proc sqlite3_load_extension*(db: Sqlite3; file: cstring; procName: cstring;
    errMsg: ptr cstring): cint {.cdecl, importc, header: "sqlite3.h".}
proc sqlite3_prepare_v2*(db: Sqlite3; sql: cstring; nByte: cint; stmt: var Sqlite3Stmt;
    tail: pointer): cint {.cdecl, importc, header: "sqlite3.h".}
proc sqlite3_finalize*(stmt: Sqlite3Stmt): cint {.cdecl, importc, header: "sqlite3.h".}
proc sqlite3_reset*(stmt: Sqlite3Stmt): cint {.cdecl, importc, header: "sqlite3.h".}
proc sqlite3_clear_bindings*(stmt: Sqlite3Stmt): cint {.cdecl, importc,
    header: "sqlite3.h".}
proc sqlite3_step*(stmt: Sqlite3Stmt): cint {.cdecl, importc, header: "sqlite3.h".}
proc sqlite3_bind_text*(stmt: Sqlite3Stmt; index: cint; value: cstring; n: cint;
    destructor: Sqlite3Destructor): cint {.cdecl, importc, header: "sqlite3.h".}
proc sqlite3_bind_blob*(stmt: Sqlite3Stmt; index: cint; value: pointer; n: cint;
    destructor: Sqlite3Destructor): cint {.cdecl, importc, header: "sqlite3.h".}
proc sqlite3_bind_int*(stmt: Sqlite3Stmt; index: cint; value: cint): cint {.cdecl, importc,
    header: "sqlite3.h".}
proc sqlite3_bind_int64*(stmt: Sqlite3Stmt; index: cint; value: int64): cint {.cdecl, importc,
    header: "sqlite3.h".}
proc sqlite3_bind_null*(stmt: Sqlite3Stmt; index: cint): cint {.cdecl, importc,
    header: "sqlite3.h".}
proc sqlite3_column_type*(stmt: Sqlite3Stmt; column: cint): cint {.cdecl, importc,
    header: "sqlite3.h".}
proc sqlite3_column_int*(stmt: Sqlite3Stmt; column: cint): cint {.cdecl, importc,
    header: "sqlite3.h".}
proc sqlite3_column_int64*(stmt: Sqlite3Stmt; column: cint): int64 {.cdecl, importc,
    header: "sqlite3.h".}
proc sqlite3_column_double*(stmt: Sqlite3Stmt; column: cint): cdouble {.cdecl, importc,
    header: "sqlite3.h".}
proc sqlite3_column_text*(stmt: Sqlite3Stmt; column: cint): cstring {.cdecl, importc,
    header: "sqlite3.h".}

proc sqliteTransient*(): Sqlite3Destructor {.inline.} =
  result = cast[Sqlite3Destructor](cast[pointer](-1))
