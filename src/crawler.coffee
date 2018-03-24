fs        = require 'fs'
sleep     = require 'sleep'
cheerio   = require 'cheerio'
request   = require 'request'
Sequelize = require 'sequelize'


config = JSON.parse fs.readFileSync('./config.json', 'utf-8')


log = console.log
info = (str) -> log chalk.magenta.bold '[' + chalk.cyan.bold "INFO" + chalk.magenta.bold ']' + " " + chalk.black str
error = (str) -> log chalk.magenta.bold '[' + chalk.red.bold "ERROR" + chalk.magenta.bold ']' + " " + chalk.red.bold str
warn = (str) -> log chalk.magenta.bold '['  + chalk.yellow.bold "WARN"  + chalk.magenta.bold "]" + " " + chalk.bold.yellow str



sequelize = new Sequelize config["Database"]["Database"], config["Database"]["Username"], config["Database"]["Password"], {
  host: config["Database"]["Host"],
  dialect: config["Database"]["Dialect"],

  pool: {
    max: 5,
    min: 0,
    acquire: 30000,
    idle: 10000
  },

  # SQLite only
  storage: config["Database"]["Storage"],

  # http://docs.sequelizejs.com/manual/tutorial/querying.html#operators
  operatorsAliases: false
}


Page = sequelize.define config["Database"]["Prefix"] + "pages", {
  url: Sequelize.STRING,
  title: Sequelize.STRING,
  added: Sequelize.TIME,
  active: Sequelize.BOOLEAN,
  blocked: Sequelize.BOOLEAN
}


if config["Development"]
  sequelize.sync {force: true}
else
  do sequelize.sync


START_URL = config["StartPage"]

pagesToCrawl = [START_URL, "https://www.fastboyscouts.de"]
pagesVisited = []

max_connections = config["MaxConnections"]
connections = 0

pagesToCrawl.push START_URL

crawl = () ->
  nextPage = do pagesToCrawl.pop
  if nextPage in pagesVisited
    do crawl
  else
    pagesVisited.push nextPage
    crawlPage nextPage


crawlPage = (p) ->
  connections++
  console.log("v"+connections+": "+p)
  blockedOk = false
  if config["OnlyFilter"]
    blockedOk = false
    config["FilterTags"].forEach (item) ->
      if blockedOk == false
        if p.includes item
          blockedOk = true
  else
    blockedOk = true

  if blockedOk
    if config["WordBlocker"]
      config["BlockedWords"].forEach (item) ->
        if blockedOk
          if p.includes item
            blockedOk = false

  if blockedOk
    console.log "Visiting " + p
    request p, (error, response, body) ->
       if error != null
         if error.length > 0
           do crawl
           return null
       # Check status code (200 is HTTP OK)
       if response
         if response != null
           if response.statusCode != null
             console.log "Status code: " + response.statusCode
             if response.statusCode == 200
               # Parse the document body
               $ = cheerio.load body
               console.log "Page title:  " + $('title').text()
               Page.build({url: p, title: $('title').text(), active: true, blocked: false}).save()
               collectInternalLinks($).forEach (item) ->
                  pagesToCrawl.push item
                do crawl
              else
                do crawl
            else
              do crawl
          else
            do crawl
        else
          do crawl
  else
    do crawl





collectInternalLinks = ($) ->
  allRelativeLinks = []
  allAbsoluteLinks = []

  relativeLinks = $ "a[href^='/']"
  relativeLinks.each () ->
    allRelativeLinks.push $(this).attr 'href'

  absoluteHttpLinks = $ "a[href^='http']"
  absoluteHttpLinks.each () ->
    allAbsoluteLinks.push $(this).attr 'href'

  absoluteHttpsLinks = $ "a[href^='https']"
  absoluteHttpsLinks.each () ->
    allAbsoluteLinks.push $(this).attr 'href'

  return allAbsoluteLinks

  console.log "Found " + allRelativeLinks.length + " relative links"
  console.log "Found " + allAbsoluteLinks.length + " absolute links"

do crawl
