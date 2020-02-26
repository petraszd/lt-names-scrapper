import algorithm
import asyncdispatch
import asyncfutures
import htmlparser
import httpclient
import strformat
import strtabs
import strutils
import xmltree


const MAIN_URL = "http://vardai.vlkk.lt/"
const LETTERS_MENU_ID = "recommend"
const LETTERS_LINKS_CLASS_NAME = "recommend__links"
const MALE_CLASS_NAME = "names_list__links names_list__links--man"
const FEMALE_CLASS_NAME = "names_list__links names_list__links--woman"
const NAMES_LIST_CLASS_NAME = "section"
const MALES_FILENAME = "berniukai.txt"
const FEMALES_FILENAME = "mergaites.txt"


type NamesFromPage = ref object
  females: seq[string]
  males: seq[string]


proc getMenuNode(rootNode: XmlNode): XmlNode =
  result = nil

  var ulNodes = newSeq[XmlNode]()
  findAll(rootNode, "section", ulNodes, caseInsensitive = true)
  for node in ulNodes:
    let attrs = attrs(node)
    if attrs != nil and hasKey(attrs, "id") and attrs["id"] == LETTERS_MENU_ID:
      result = node
      break

    assert(result != nil, "Site menu does not exist")


proc getNamesWrapperNode(rootNode: XmlNode): XmlNode =
  result = nil

  var ulNodes = newSeq[XmlNode]()
  findAll(rootNode, "section", ulNodes, caseInsensitive = true)
  for node in ulNodes:
    let attrs = attrs(node)
    if attrs != nil and getOrDefault(attrs, "class") == NAMES_LIST_CLASS_NAME:
      result = node
      break

  assert(result != nil, "Names list does not exist")


proc getLetterLinks(links: var seq[string]) =
  var client = newHttpClient()

  let rootNode = parseHtml(client.getContent(MAIN_URL))
  let menuNode = getMenuNode(rootNode)

  var linkNodes = newSeq[XmlNode]()
  findAll(menuNode, "a", linkNodes, caseInsensitive = true)

  for node in linkNodes:
    let attrs = attrs(node)
    if attrs != nil and getOrDefault(attrs, "class") == LETTERS_LINKS_CLASS_NAME:
      add(links, attrs["href"])


proc getNamesFromPage(link: string): Future[NamesFromPage] {.async.} =
  var males = newSeq[string]()
  var females = newSeq[string]()

  var client = newAsyncHttpClient()
  let future = client.getContent(link)
  yield future

  assert(not future.failed, &"something is wrong with {link}")
  let rootNode = parseHtml(future.read())

  let namesWrapperNode = getNamesWrapperNode(rootNode)

  var linkNodes = newSeq[XmlNode]()
  findAll(namesWrapperNode, "a", linkNodes, caseInsensitive = true)

  for node in linkNodes:
    let attrs = attrs(node)
    if attrs == nil:
      continue

    let className = getOrDefault(attrs, "class")
    if className == MALE_CLASS_NAME:
      add(males, innerText(node))
    if className == FEMALE_CLASS_NAME:
      add(females, innerText(node))

    result = NamesFromPage(males: males, females: females)


proc writeToFile(names: seq[string], filename: string) =
  var f: File
  assert(open(f, filename, fmWrite) != false)

  for name in names:
    writeLine(f, name)

  close(f)


proc main() {.async.} =
  var links = newSeq[string]()
  getLetterLinks(links)

  var futures = newSeq[Future[NamesFromPage]]()
  for link in links:
    add(futures, getNamesFromPage(link))

  let namesFromAllPages = await all(futures)

  var males: seq[string] = @[]
  var females: seq[string] = @[]

  for names in namesFromAllPages:
    for name in names.males:
      add(males, name)
    for name in names.females:
      add(females, name)

  sort(males)
  writeToFile(males, MALES_FILENAME)
  sort(females)
  writeToFile(females, FEMALES_FILENAME)


waitFor(main())
