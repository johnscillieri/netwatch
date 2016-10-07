# Originally from https://github.com/coffeepots/niminifiles
# Minor changes made to support netwatch

## Provide simple wrapper for ini files.
## Files are read in their totality and arranged as a dictionary of:
## section title, value title, value
import os, tables, strutils

type
  IniFile* = ref object
    filename*: string
    sections*: OrderedTableRef[string, OrderedTableRef[string, string]]

proc clear*(inifile: var IniFile) =
  inifile.sections = newOrderedTable[string, OrderedTableRef[string, string]]()

proc newIniFile*: IniFile =
  new(result)
  result.clear()

proc find*(inifile: IniFile, section: string, key: string): string =
  ## Look up key in section.
  var
    lkey = key.toLower
    lsec = section.toLower

  result = ""
  if inifile.sections.hasKey(lsec) and inifile.sections[lsec].hasKey(lkey):
    result = inifile.sections[lsec][lkey]

proc section*(inifile: IniFile, section: string): OrderedTableRef[string, string] =
  ## Look up key in section.
  let lsec = section.toLower

  if not inifile.sections.hasKey(lsec):
    inifile.sections[lsec] = newOrderedTable[string,string]()
  result = inifile.sections[lsec]

template `[]`*(inifile: IniFile, section_name: string): OrderedTableRef[string, string] =
  inifile.section(section_name)

proc find*(inifile: IniFile, key: string): string =
  ## Look through all sections for a key.
  # here we don't specify a section, so we need to search all items.
  var lkey = key.toLower
  result = ""
  for section in inifile.sections.pairs:
    var secItems = section[1]

    if secItems.hasKey(lkey):
      result = secItems[lkey]
      break

proc loadIni*(inifile: var IniFile, filename: string = ""): bool =
  ## Load ini file and split into dictionaries.
  ## Double quotes are stripped.
  # assumes inifile has been initialised with filename, otherwise initialises for you
  # returns true when at least one key/value pair has been registered
  result = false
  if inifile == nil: inifile = newIniFile()
  inifile.clear
  if filename != "": inifile.filename = filename

  var
    curSection: string = ""

  if not fileExists(iniFile.filename):
    return false

  for line in lines inifile.filename:
    let sLine = line.strip

    if sLine.len > 2 and sLine.startsWith("[") and sLine.endsWith("]"):
      # this is a section
      var newTable = newOrderedTable[string, string]()
      curSection = substr(sLine.toLower, 1, sLine.len - 2)
      inifile.sections.add(curSection, newTable)
    elif sLine.startsWith(";") or sLine.startsWith("#"):
      # comment
      discard
    elif sLine != "" and sLine.len > 3:
      # Anything else is checked to be a key/value pair
      let sepPoint = sLine.find("=")

      if sepPoint > 0:
        # qualifies as a key/value pair
        var sectionItems: OrderedTableRef[string, string]

        if not inifile.sections.hasKey(curSection):
          # handle items under no/blank section
          sectionItems = newOrderedTable[string, string]()
          inifile.sections.add(curSection, sectionItems)
        else:
          # retrieve from existing section table
          sectionItems = inifile.sections.mget(curSection)

        let
          # lsLine = sLine.toLower
          # note: quotes are stripped
          k = sLine.subStr(0, sepPoint - 1).replace("\"")
          v = sLine.subStr(sepPoint + 1).replace("\"")
        sectionItems.add(k.strip().toLower, v.strip())
        result = true


proc `$`*(ini: IniFile): string =
  ## Return ini file as structured string.
  var lines = newSeq[string]()
  for sec_name, sec_entries in ini.sections:
    lines.add( "[" & sec_name & "]" )
    for key, value in sec_entries:
      lines.add( key & " = " & value )
    lines.add("")
  result = lines.join("\n")

when isMainModule:
  var ini = newIniFile()
  ini.filename = getCurrentDir().joinPath("temp.ini")
  if ini.loadIni:
    echo "Full ini file:"
    echo ini

    var
      item = ini.find("name")
      sectionItem = ini.find("section", "name")

    echo "item: ", item
    echo "section item: ", sectionItem
  else:
    echo "File not found or doesn't contain any key/value pairs."

