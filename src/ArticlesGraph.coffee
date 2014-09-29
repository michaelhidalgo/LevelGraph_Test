require('fluentnode')
fs         = require('fs')
levelup    = require("level"        )
leveldown  = require('leveldown'    )
levelgraph = require('levelgraph'   )

class ArticlesGraph
    constructor: ->
                    #console.log('in ArticlesGraph ctor')
                    @dbPath     = './db'
                    #@level      = levelup   (@dbPath)
                    #@db         = levelgraph(@level)
                    @level      = null
                    @db         = null
                    @dataFile   = './src/article-data.json'
                    @data       = null
    
    #Setup methods
    
    closeDb: (callback)->
                if(@level == null)                    
                    callback()
                else                
                    @level.close =>
                        @db.close =>
                            @db    = null
                            @level = null
                            callback()
                
    openDb : ->
                @level      = levelup   (@dbPath)
                @db         = levelgraph(@level)
                
    deleteDb: ->
        console.log 'Deleting the articleDB'
        require('child_process').spawn('rm', ['-Rv',@dbPath])
            
    dataFilePath: -> process.cwd().path.join(@dataFile)
    dataFromFile: ()-> JSON.parse fs.readFileSync(@dataFilePath(), "utf8")
    
    loadTestData: (callback) =>
        if (@db==null)
            @openDb()
        @data = @dataFromFile()
        @db.put @data, callback
    
    # Search methods
    
    allData: (callback)->
        @db.search [{
                        subject  : @db.v("subject"),
                        predicate: @db.v("predicate"),
                        object   : @db.v("object"),
                    }], callback
     
    query: (key, value, callback)->
        switch key
            when "subject"      then @db.get { subject: value}, callback
            when "predicate"    then @db.get { predicate: value}, callback
            when "object"       then @db.get { object: value}, callback
            else callback(null,[])
                    
        
        
    articlesInView_by_Id: (viewId, callback) ->
        #console.log("\n >  getting all viewArticles from #{viewId}")
        @db.get object: viewId, callback
        
    articlesInView_by_Name: (viewName, callback) ->
        #console.log("\n > getting all viewArticles from #{viewName}")
        @db.search [{
                        subject  : @db.v("x"),
                        predicate: "Title",
                        object   : viewName
                    },
                    {
                        subject  : @db.v("y"),
                        predicate: "View",
                        object   : @db.v("x")
                    },
                    {
                        subject  : @db.v("y"),
                        predicate: "is an",
                        object   : "Article"
                    },
                    {
                        subject   : @db.v("y"),
                        predicate : @db.v("predicate"),
                        object    : @db.v("object"),
                    },
                    ],
                        materialized: {
                                            #view_Name: viewName
                                            view_id  : @db.v('x')
                                            action   : "contains",
                                            subject  : @db.v("y")
                                            predicate: @db.v("predicate")
                                            object   : @db.v("object")
                                      },callback
    
    searchGraph : (viewName,callback)->
        @db.search [{   subject  : @db.v("id"       ),  predicate: "Title"    ,  object   : viewName                }  # find item with Title 
                    {   subject  : @db.v("id"       ),  predicate: "is an"    ,  object   : @db.v("Folder")         }  #""
                    {   subject  : @db.v("viewId"   ),  predicate: "Contains" ,  object   : @db.v("childViewId")    }
                    {   subject  : @db.v("articleId"),  predicate: "View"     ,  object   : @db.v("childViewId")    }
                    {   subject  : @db.v("articleId"),  predicate: "is an"    ,  object   : @db.v("Article")        }
                    {   subject  : @db.v("articleId"),  predicate: @db.v("predicate") ,  object   : @db.v("object") }
                    ],
                    materialized: {
                                        viewName    : viewName
                                        subject     : @db.v("viewId")
                                        childViewId : @db.v("childViewId")
                                        articleId   : @db.v("articleId")
                                        predicate   : @db.v("predicate")
                                        object      : @db.v("object")                                        
                                  }
                    callback

    createSearchData: (folderName,callback)->        
        
        searchData              = {}
        
        setDefaultValues = ->
            searchData.title        = folderName
            searchData.containers   = []
            searchData.resultsTitle = "n/n results showing"
            searchData.results      = []
            searchData.filters      = []
        
        metadata = {}
        
        mapMetadata = ()=>
            for item of metadata when typeof(metadata[item]) != 'function'
                filter = {}
                filter.title   = item
                filter.results = []
                for mapping of metadata[item]
                    if typeof(metadata[item][mapping]) != 'function'
                        result = { title : mapping , size: metadata[item][mapping]}
                        filter.results.push(result)                        
                searchData.filters.push(filter)
            callback(searchData)
            
        mapArticles = (articles) =>            
            if (articles.empty())                
                mapMetadata()
            else
                article = articles.pop()
                @query 'subject', article, (err,data) ->
                    result = { title: null, link: null , id: null, summary: null, score : null }
                    for item in data
                        switch item.predicate
                            when 'Guid'     then result.id = item.object
                            when 'Title'    then result.title = item.object
                            when 'Summary'  then result.summary = item.object
                            when 'is an'    then #do Nothing
                            when 'View'     then #do Nothing
                            else 
                                if not metadata[item.predicate] then metadata[item.predicate] = {}
                                if metadata[item.predicate][item.object] 
                                    metadata[item.predicate][item.object]++
                                else
                                    metadata[item.predicate][item.object] = 1
                    result.link = 'https://tmdev01-sme.teammentor.net/'+result.id
                    result.score = 0                    
                    searchData.results.push(result)
                    mapArticles(articles)
        
        mapViews = (viewsToMap,articles) =>                
            if (viewsToMap.empty())
                mapArticles(articles)
            else
                viewToMap = viewsToMap.pop()                
                @query 'subject', viewToMap.id, (err,data) ->
                    container = { title: null, id: null, size : viewToMap.size }
                    for item in data
                        switch item.predicate
                            when 'Guid'  then container.id = item.object
                            when 'Title' then container.title = item.object                            
                    searchData.containers.push(container)    
                    mapViews(viewsToMap,articles)
            
        mapResults = (err,data) =>            
            viewsCount = {}
            articles   = []
            for item in data                
                articles.push(item.article)
                if viewsCount[item.view] then viewsCount[item.view]++ else viewsCount[item.view] = 1
                
            searchData.resultsTitle = "#{articles.length}/#{data.length} results showing"
            
            viewsToMap = ({ id: key, size: viewsCount[key]} for key of viewsCount when typeof(viewsCount[key]) != 'function')
            
            mapViews(viewsToMap, articles)
            
        setDefaultValues()        
        @db.nav("Data Validation").archIn('Title'    ).as('folder')
                                  .archOut('Contains').as('view')
                                  .archIn('View'     ).as('article')
                                  .solutions(mapResults)        
        
module.exports = ArticlesGraph
