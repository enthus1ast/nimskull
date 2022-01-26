## This module implements formatting logic for colored text diffs - both
## multiline and inline.
##
## All formatting is generated in colored text format and can be later
## formatted in both plaintext and formatted manners using
## `colortext.toString`

import ./diff, ./colortext
import std/[sequtils, strutils, strformat, algorithm]

export toString, `$`, myersDiff, shiftDiffed

proc colorDollar*[T](arg: T): ColText = toColText($arg)

type
  DiffFormatConf* = object
    ## Diff formatting configuration
    maxUnchanged*: int ## Max number of the unchanged lines after which
    ## they will be no longer show. Can be used to compact large diffs with
    ## small mismatched parts.
    maxUnchangedWords*: int ## Max number of the unchanged words in a
    ## single line. Can be used to compact long lines with small mismatches
    showLines*: bool ## Show line numbers in the generated diffs
    lineSplit*: proc(str: string): seq[string] ## Split line
    ## into chunks for formatting
    sideBySide*: bool ## Show line diff with side-by-side (aka github
    ## 'split' view) or on top of each other (aka 'unified')
    explainInvisible*: bool ## If diff contains invisible characters -
    ## trailing whitespaces, control characters, escapes and ANSI SGR
    ## formatting - show them directly.
    inlineDiffSeparator*: ColText ## Text to separate words in the inline split
    formatChunk*: proc(
        text: string,
        mode, secondary: SeqEditKind,
        inline: bool
    ): ColText ##  Format
    ## mismatched text. `mode` is the mismatch kind, `secondary` is used
    ## for `sekChanged` to annotated which part was deleted and which part
    ## was added.
    groupInline*: bool ## For inline edit operations - group cosecutive
    ## edit operations into single chunks.
    explainChar*: proc(ch: char): string ## Convert invisible character
    ## (whitespace or control) to human-readable representation -

proc chunk(
    conf: DiffFormatConf, text: string,
    mode: SeqEditKind, secondary: SeqEditKind = mode,
    inline: bool = false
  ): ColText =
  ## Format text mismatch chunk using `formatChunk` callback
  conf.formatChunk(text, mode, secondary, inline)

func splitKeepSeparator*(str: string, sep: set[char] = {' '}): seq[string] =
  ## Default implementaion of the line splitter - split on `sep` characters
  ## but don't discard them - they will be present in the resulting output.
  var prev = 0
  var curr = 0
  while curr < str.len:
    if str[curr] in sep:
      if prev != curr:
        result.add str[prev ..< curr]

      prev = curr
      while curr < str.high and str[curr + 1] == str[curr]:
        inc curr

      result.add str[prev .. curr]
      inc curr
      prev = curr

    else:
      inc curr

  if prev < curr:
    result.add str[prev ..< curr]

proc formatDiffed*[T](
    ops: seq[SeqEdit],
    oldSeq, newSeq: seq[T],
    conf: DiffFormatConf
  ): tuple[oldLine, newLine: ColText] =
  ## Generate colored formatting fothe levenshtein edit operation using
  ## format configuration. Return old formatted line and new formatted line.

  var unchanged = 0
  var oldLine: seq[ColText]
  var newLine: seq[ColText]
  for idx, op in ops:
    case op.kind:
      of sekKeep:
        if unchanged < conf.maxUnchanged:
          oldLine.add conf.chunk(oldSeq[op.sourcePos], sekKeep)
          newLine.add conf.chunk(newSeq[op.targetPos], sekKeep)
          inc unchanged

      of sekDelete:
        oldLine.add conf.chunk(oldSeq[op.sourcePos], sekDelete)
        unchanged = 0

      of sekInsert:
        newLine.add conf.chunk(newSeq[op.targetPos], sekInsert)
        unchanged = 0

      of sekReplace:
        oldLine.add conf.chunk(oldSeq[op.sourcePos], sekReplace, sekDelete)
        newLine.add conf.chunk(newSeq[op.targetPos], sekReplace, sekInsert)
        unchanged = 0

      of sekNone:
        assert false

      of sekTranspose:
        discard

  return (
    oldLine.join(conf.inlineDiffSeparator),
    newLine.join(conf.inlineDiffSeparator)
  )




func visibleName(ch: char): tuple[unicode, ascii: string] =
  ## Get visible name of the character.
  case ch:
    of '\x00': ("␀", "[NUL]")
    of '\x01': ("␁", "[SOH]")
    of '\x02': ("␂", "[STX]")
    of '\x03': ("␃", "[ETX]")
    of '\x04': ("␄", "[EOT]")
    of '\x05': ("␅", "[ENQ]")
    of '\x06': ("␆", "[ACK]")
    of '\x07': ("␇", "[BEL]")
    of '\x08': ("␈", "[BS]")
    of '\x09': ("␉", "[HT]")
    of '\x0A': ("␤", "[LF]")
    of '\x0B': ("␋", "[VT]")
    of '\x0C': ("␌", "[FF]")
    of '\x0D': ("␍", "[CR]")
    of '\x0E': ("␎", "[SO]")
    of '\x0F': ("␏", "[SI]")
    of '\x10': ("␐", "[DLE]")
    of '\x11': ("␑", "[DC1]")
    of '\x12': ("␒", "[DC2]")
    of '\x13': ("␓", "[DC3]")
    of '\x14': ("␔", "[DC4]")
    of '\x15': ("␕", "[NAK]")
    of '\x16': ("␖", "[SYN]")
    of '\x17': ("␗", "[ETB]")
    of '\x18': ("␘", "[CAN]")
    of '\x19': ("␙", "[EM]")
    of '\x1A': ("␚", "[SUB]")
    of '\x1B': ("␛", "[ESC]")
    of '\x1C': ("␜", "[FS]")
    of '\x1D': ("␝", "[GS]")
    of '\x1E': ("␞", "[RS]")
    of '\x1F': ("␟", "[US]")
    of '\x7f': ("␡", "[DEL]")
    of ' ': ("␣", "[SPC]") # Space
    else: ($ch, $ch)

proc toVisibleNames(conf: DiffFormatConf, str: string): string =
  ## Convert all characters in the string into visible ones
  for ch in str:
    result.add conf.explainChar(ch)


proc toVisibleNames(conf: DiffFormatConf, split: seq[string]): seq[string] =
  ## Convert all charactersw in all strings into visible ones.
  if 0 < split.len():
    for part in split:
      result.add conf.toVisibleNames(part)

const Invis = { '\x00' .. '\x1F', '\x7F' }

func scanInvisible(text: string, invisSet: var set[char]): bool =
  ## Scan string for invisible characters from right to left, updating
  ## active invisible set as needed.
  var chIdx = text.high
  while 0 <= chIdx:
    if text[chIdx] in invisSet:
      return true

    else:
      invisSet = Invis

    dec chIdx

func hasInvisible*(text: string, startSet: set[char] = Invis + {' '}): bool =
  ## Does string have significant invisible characters?
  var invisSet = startSet
  if scanInvisible(text, invisSet):
    return true

func hasInvisible*(text: seq[string]): bool =
  ## Do any of strings in text have signfificant invisible characters.
  var idx = text.high
  var invisSet = Invis + {' '}
  while 0 <= idx:
    # Iterate over all items from righ to left - until we found first
    # visible character space is also considered significant, but removed
    # afterwards, so `" a"/"a"` is not considered to have invisible
    # characters.
    if scanInvisible(text[idx], invisSet):
      return true
    dec idx


func hasInvisibleChanges(diff: seq[SeqEdit], oldSeq, newSeq: seq[string]): bool =
  ## Is any change in the edit sequence invisible?
  var start = Invis + {' '}

  proc invis(text: string): bool =
    result = scanInvisible(text, start)

  # Iterate over all edits from right to left, updating active set of
  # invisible characters as we got.
  var idx = diff.high
  while 0 <= idx:
    let edit = diff[idx]
    case edit.kind:
      of sekDelete:
        if oldSeq[edit.sourcePos].invis():
          return true

      of sekInsert:
        if newSeq[edit.targetPos].invis():
          return true

      of sekNone, sekTranspose:
        discard

      of sekKeep:
        # Check for kept characters - this will update 'invisible' set if
        # any found, so edits like `" X" -> "X"` are not considered as 'has
        # invisible'
        if oldSeq[edit.sourcePos].invis():
          discard

      of sekReplace:
        if oldSeq[edit.sourcePos].invis() or
           newSeq[edit.targetPos].invis():
          return true

    dec idx

func diffFormatter*(useUncide: bool = true): DiffFormatConf =
  ## Default implementation of the diff formatter
  ##
  ## - split lines by whitespace
  ## - no hidden lines or workds
  ## - deleted: red, inserted: green, changed: yellow
  ## - explain invisible differences with unicode
  DiffFormatConf(
    # Don't hide inline edit lines
    maxUnchanged:       high(int),
    # Group edit operations for inline diff by default
    groupInline:        true,
    # Show differences if there are any invisible characters
    explainInvisible:   true,
    # Don't hide inline edit words
    maxUnchangedWords:  high(int),
    showLines:          false,
    explainChar:        (
      proc(ch: char): string =
        let (uc, ascii) = visibleName(ch)
        if useUncide: uc else: ascii
    ),
    lineSplit:          (
      # Split by whitespace
      proc(a:    string): seq[string] = splitKeepSeparator(a)
    ),
    sideBySide:         false,
    formatChunk:        (
      proc(word: string, mode, secondary: SeqEditKind, inline: bool): ColText =
        case mode:
          of sekDelete:                word + fgRed
          of sekInsert:                word + fgGreen
          of sekKeep:                  word + fgDefault
          of sekNone:                  word + fgDefault
          of sekReplace, sekTranspose:
            if inline and secondary == sekDelete:
              "[" & (word + fgYellow) & " -> "

            elif inline and secondary == sekInsert:
              (word + fgYellow) & "]"

            else:
              word + fgYellow
    )
  )

proc formatLineDiff*(
    old, new: string, conf: DiffFormatConf,
  ): tuple[oldLine, newLine: ColText] =
  ## Format single line diff into old/new line edits. Optionally explain
  ## all differences using options from `conf`

  let
    oldSplit = conf.lineSplit(old)
    newSplit = conf.lineSplit(new)
    diffed = levenshteinDistance[string](oldSplit, newSplit)

  var oldLine, newLine: ColText

  if conf.explainInvisible and (
     diffed.operations.hasInvisibleChanges(oldSplit, newSplit) or
     oldSplit.hasInvisible() or
     newSplit.hasInvisible()
  ):
    (oldLine, newLine) = formatDiffed(
      diffed.operations,
      conf.toVisibleNames(oldSplit),
      conf.toVisibleNames(newSplit),
      conf
    )

  else:
    (oldLine, newLine) = formatDiffed(
      diffed.operations,
      oldSplit, newSplit,
      conf
    )

  return (oldLine, newLine)


template groupByIt[T](sequence: seq[T], op: untyped): seq[seq[T]] =
  ## Group input sequence by value of the `op` into smaller subsequences
  var res: seq[seq[T]]
  var i = 0
  for item in sequence:
    if i == 0:
      res.add @[item]

    else:
      if ((block:
             let it {.inject.} = res[^1][0]; op)) ==
         ((block:
             let it {.inject.} = item; op)):
        res[^1].add item

      else:
        res.add @[item]

    inc i

  res

proc formatInlineDiff*(
    src, target: seq[string],
    diffed: seq[SeqEdit],
    conf: DiffFormatConf
  ): ColText =
  ## Format inline edit operations for `src` and `target` sequences using
  ## list of sequence edit operations `diffed`, formatting the result using
  ## `conf` formatter. Consecutive edit operations are grouped together if
  ## `conf.groupInline` is set to `true`

  var start = Invis + {' '}
  var chunks: seq[ColText]
  proc push(
      text: string,
      mode: SeqEditKind,
      secondary: SeqEditKind = mode,
      toLast: bool = false,
      inline: bool = false
    ) =
    ## Push single piece of changed text to the resulting chunk sequence
    ## after scanning for invisible characters. if `toLast` then add
    ## directly to the last chunk - needed to avoid intermixing edit
    ## visuals for the `sekReplace` edits which are the most important of
    ## them all
    var chunk: ColText
    if conf.explainInvisible and scanInvisible(text, start):
      chunk = conf.chunk(
        conf.toVisibleNames(text), mode, secondary, inline = inline)

    else:
      chunk = conf.chunk(
        text, mode, secondary, inline = inline)

    if toLast:
      chunks[^1].add chunk

    else:
      chunks.add chunk

  let groups =
    if conf.groupInline:
      # Group edit operations by chunk - `[ins], [ins], [ins] -> [ins, ins, ins]`
      #
      # This is not specifically important for insertions and deletions,
      # but pretty much mandatory for the 'change' operation, if we don't
      # want to end up with the `h->He->El->Lo->O` instead of
      # `hello->HELLO`
      groupByIt(diffed, it.kind)

    else:
      # Treat each group as a single edit operation if needed
      mapIt(diffed, @[it])

  var gIdx = groups.high
  while 0 <= gIdx:
    case groups[gIdx][0].kind:
      of sekKeep:
        var buf: string
        for op in groups[gIdx]:
          buf.add src[op.sourcePos]

        push(buf, sekKeep)

      of sekNone, sekTranspose:
        discard

      of sekInsert:
        var buf: string
        for op in groups[gIdx]:
          buf.add target[op.targetPos]

        push(buf, sekInsert)

      of sekDelete:
        var buf: string
        for op in groups[gIdx]:
          buf.add src[op.sourcePos]

        push(buf, sekDelete)

      of sekReplace:
        var sourceBuf, targetBuf: string
        for op in groups[gIdx]:
          sourceBuf.add src[op.sourcePos]
          targetBuf.add target[op.targetPos]

        push(sourceBuf, sekReplace, sekDelete, inline = true)
        # Force add directly to the last chunk
        push(targetBuf, sekReplace, sekInsert, toLast = true, inline = true)

    dec gIdx

  # Because we iterated from right to left, all edit operations are placed
  # in reverse as well, so this needs to be fixed
  return chunks.reversed().join(conf.inlineDiffSeparator)


proc formatInlineDiff*(
    src, target: string, conf: DiffFormatConf
  ): ColText =
  ## Generate inline string editing annotation for the source and target
  ## string. Use `conf` for message mismatch configuration.
  let
    src = conf.lineSplit(src)
    target = conf.lineSplit(target)

  return formatInlineDiff(
    src, target, levenshteinDistance[string](src, target).operations, conf)

proc formatDiffed*(
    shifted: ShiftedDiff,
    oldSeq, newSeq: openarray[string],
    conf: DiffFormatConf = diffFormatter()
  ): ColText =
  ## Format shifted multiline diff
  ##
  ## `oldSeq`, `newSeq` - sequence of lines (no newlines in strings
  ## assumed) that will be formatted.

  var
    oldText, newText: seq[tuple[text: ColText, changed: bool]]
    lhsMax = 0

  # Max line number len for left and right side
  let maxLhsIdx = len($shifted.oldShifted[^1].item)
  let maxRhsIdx = len($shifted.newShifted[^1].item)

  proc editFmt(edit: SeqEditKind, idx: int, isLhs: bool): ColText =
    ## Format prefix for edit operation for line at index `idx`
    let editOps = [
      sekNone:      "?",
      sekKeep:      "~",
      sekInsert:    "+",
      sekReplace:   "-+",
      sekDelete:    "-",
      sekTranspose: "^v"
    ]

    var change: string
    if edit == sekNone and not isLhs:
      change = editOps[edit]

    else:
      change = alignLeft(editOps[edit], 2)

    if conf.showLines:
      if edit == sekNone:
        change.add align(" ", maxLhsIdx)

      elif isLhs:
        change.add align($idx, maxLhsIdx)

      else:
        change.add align($idx, maxRhsIdx)

    if edit == sekReplace:
      return conf.chunk(change, edit, if isLhs: sekDelete else: sekInsert)

    else:
      return conf.chunk(change, edit, )

  # Number of unchanged lines
  var unchanged = 0
  for (lhs, rhs, lhsDefault, rhsDefault, idx) in zipToMax(
    shifted.oldShifted, shifted.newShifted
  ):
    if lhs.kind == sekKeep and rhs.kind == sekKeep:
      if unchanged < conf.maxUnchanged:
        inc unchanged

      else:
        continue

    else:
      unchanged = 0

    oldText.add((editFmt(lhs.kind, lhs.item, true), true))

    newText.add((
      editFmt(rhs.kind, rhs.item, false),
      # Only newly inserted lines need to be formatted for the unified
      # diff, everything else is displayed on the 'original' version.
      not conf.sideBySide and rhs.kind in {sekInsert}
    ))

    var lhsEmpty, rhsEmpty: bool
    if not lhsDefault and
       not rhsDefault and
       lhs.kind == sekDelete and
       rhs.kind == sekInsert:

      let (oldLine, newLine) = formatLineDiff(
        oldSeq[lhs.item],
        newSeq[rhs.item],
        conf
      )

      oldText[^1].text.add oldLine
      newText[^1].text.add newLine


    elif rhs.kind == sekInsert:
      let tmp = newSeq[rhs.item]
      rhsEmpty = tmp.len == 0
      newText[^1].text.add conf.chunk(tmp, sekInsert)

    elif lhs.kind == sekDelete:
      let tmp = oldSeq[lhs.item]
      lhsEmpty = tmp.len == 0
      oldText[^1].text.add conf.chunk(tmp, sekDelete)

    else:
      let ltmp = oldSeq[lhs.item]
      lhsEmpty = ltmp.len == 0
      oldText[^1].text.add conf.chunk(ltmp, lhs.kind)

      let rtmp = newSeq[rhs.item]
      rhsEmpty = rtmp.len == 0
      newText[^1].text.add conf.chunk(rtmp, rhs.kind)


    if lhsEmpty and idx < shifted.oldShifted.high:
      oldText[^1].text.add conf.chunk(
        conf.toVisibleNames("\n"), sekDelete)

    if rhsEmpty and idx < shifted.newShifted.high:
      newText[^1].text.add conf.chunk(
        conf.toVisibleNames("\n"), sekInsert)

    lhsMax = max(oldText[^1].text.len, lhsMax)

  var first = true
  for (lhs, rhs) in zip(oldtext, newtext):
    if not first:
      # Avoid trailing newline of the diff formatting.
      result.add "\n"
    first = false

    if conf.sideBySide:
      result.add alignLeft(lhs.text, lhsMax + 3)
      result.add rhs.text

    else:
      result.add lhs.text
      if rhs.changed:
        result.add "\n"
        result.add rhs.text

proc formatDiffed*[T](
    oldSeq, newSeq: openarray[T],
    conf: DiffFormatConf,
    eqCmp: proc(a, b: T): bool = (proc(a, b: T): bool = a == b),
    strConv: proc(a: T): string = (proc(a: T): string = $a)
  ): ColText =

  formatDiffed(
    myersDiff(oldSeq, newSeq, eqCmp).shiftDiffed(oldSeq, newSeq),
    mapIt(oldSeq, strConv($it)),
    mapIt(newSeq, strConv(it)),
    conf
  )


proc formatDiffed*(
    text1, text2: string,
    conf: DiffFormatConf = diffFormatter()
  ): ColText =
  ## Format diff of two text blocks via newline split and default
  ## `formatDiffed` implementation
  formatDiffed(text1.split("\n"), text2.split("\n"), conf)
