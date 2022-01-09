discard """
  output: '''top level statements are executed!
(ival: 10, fval: 2.0)
2.0
my secret
11
12
raising VMQuit
'''
  joinable: "false"
"""

## Example program that demonstrates how to use the
## compiler as an API to embed into your own projects.

import "../../compiler" / [ast, vmdef, vm, nimeval, llstream, lineinfos, options, reports]
import std / [os]
proc initInterpreter(script: string, hook: ReportHook): Interpreter =
  let std = findNimStdLibCompileTime()
  result = createInterpreter(
    scriptName = script,
    hook = hook,
    searchPaths = [
      std,
      parentDir(currentSourcePath),
      std / "pure",
      std / "core"])

proc main() =
  let i = initInterpreter("myscript.nim")
  i.implementRoutine("*", "exposed", "addFloats", proc (a: VmArgs) =
    setResult(a, getFloat(a, 0) + getFloat(a, 1) + getFloat(a, 2))
  )
  i.evalScript()
  let foreignProc = i.selectRoutine("hostProgramRunsThis")
  if foreignProc == nil:
    quit "script does not export a proc of the name: 'hostProgramRunsThis'"
  let res = i.callRoutine(foreignProc, [newFloatNode(nkFloatLit, 0.9),
                                        newFloatNode(nkFloatLit, 0.1)])
  doAssert res.kind == nkFloatLit
  echo res.floatVal

  let foreignValue = i.selectUniqueSymbol("hostProgramWantsThis")
  if foreignValue == nil:
    quit "script does not export a global of the name: hostProgramWantsThis"
  let val = i.getGlobalValue(foreignValue)
  doAssert val.kind in {nkStrLit..nkTripleStrLit}
  echo val.strVal
  i.destroyInterpreter()

main()

block issue9180:
  proc evalString(code: string, moduleName = "script.nim") =
    let stream = llStreamOpen(code)
    let std = findNimStdLibCompileTime()
    var intr = createInterpreter(moduleName, [std, std / "pure", std / "core"])
    intr.evalScript(stream)
    destroyInterpreter(intr)
    llStreamClose(stream)

  evalString("echo 10+1")
  evalString("echo 10+2")

block error_hook:
  type VMQuit = object of CatchableError

  proc vmReport(config: ConfigRef, report: Report) {.gcsafe.} =
    if config.severity(report) == rsevError and
       config.errorCounter >= config.errorMax:

      echo "raising VMQuit"
      raise newException(VMQuit, "Script error")



  let i = initInterpreter("invalid.nim", vmReport)
  doAssertRaises(VMQuit):
    i.evalScript()
