gulp = require 'gulp'
es = require 'event-stream'
plugins = require('gulp-load-plugins')()
path = require('path')
lazypipe = require 'lazypipe'
_ = require 'lodash'
runSequence = require('run-sequence')
del = require('del')
mainBowerFiles = require('main-bower-files')
vinylPaths = require('vinyl-paths')
hi = require('highland')
yaml = require('js-yaml')

isProduction = _.startsWith(process.env['NODE_ENV'], 'prod')

gulp.task 'build', ['less', 'coffee', 'js', 'slim', 'images', 'fonts', 'inject', 'misc']

gulp.task 'default', ['connect', 'build'], ->
  gulp.start('watch')

gulp.task 'deploy', ->
  gulp.src('./build/**/*').pipe plugins.ghPages(branch: 'master')

sources =
  less: ['./assets/styles/**/*.less', '!./assets/styles/**/_*.less']
  css: ['./assets/styles/**/*.css']
  coffee: './assets/js/**/*.coffee'
  js: './assets/js/**/*.js'
  images: './assets/images/**/*'
  slim: ['./views/**/*.slim', '!./views/**/_*.slim']
  misc: './assets/misc/*'
  fonts: './assets/fonts/*'
  data: './data/*.yml'


gulp.task 'connect', ->
  plugins.connect.server({
    root: ['build'],
    port: 1337
  })

watcher = ->
  plugins.livereload.listen()
  css = './assets/styles/**/*'
  gulp.src(css)
    .pipe(plugins.watch css, plugins.batch (events, done) ->
      gulp.start('inject:css', done)
    )
    .pipe(plugins.livereload())

  removedFilter = () ->
    plugins.filter((file) ->
      file.event != 'deleted' && file.event != undefined
    )

  gulp.src sources.coffee
    .pipe(plugins.watch sources.coffee)
    .pipe(removedFilter())
    .pipe(coffeePipe())
    .pipe(plugins.livereload())
    .pipe(gulp.start 'inject:bower')

  gulp.src sources.js
    .pipe(plugins.watch sources.js)
    .pipe(removedFilter())
    .pipe(jsPipe())
    .pipe(plugins.livereload())
    .pipe(gulp.start 'inject:bower')

  gulp.src(sources.images)
    .pipe(plugins.watch sources.images)
    .pipe(removedFilter())
    .pipe(imagesPipe())
    .pipe(plugins.livereload())
    .pipe(plugins.notify {message : 'Images updated' })

  gulp.watch ['./views/**/*.slim'], ['slim', 'inject:bower']
  gulp.watch sources.data, ['slim', 'inject:bower']

  gulp.watch 'bower.json', ['inject:bower']

gulp.task 'watch', -> watcher()

sourcemapsInit = if isProduction then plugins.util.noop else plugins.sourcemaps.init
sourcemapsWrite = if isProduction then plugins.util.noop else plugins.sourcemaps.write

lessPipe = lazypipe()
  .pipe(sourcemapsInit)
  .pipe(plugins.less, {paths: [path.join(__dirname, 'bower_components')]})
  .pipe(plugins.autoprefixer)
  .pipe(plugins.concatCss, 'style.css')
  .pipe(if isProduction then plugins.minifyCss else plugins.util.noop)
  .pipe(sourcemapsWrite)
  .pipe(gulp.dest, './build/assets/styles')
  .pipe(plugins.livereload)
  .pipe(plugins.notify, {onLast: true, message : 'Less compiled' })

gulp.task 'less', ->
  gulp.src(sources.less)
    .pipe(lessPipe())

coffeePipe = lazypipe()
  .pipe(plugins.rename, (path) ->
    path.basename = path.basename.replace(/\.js$/i, '')
    return
  )
  .pipe(plugins.newer, {dest: './build/assets/js', ext: '.js'})
  .pipe(sourcemapsInit)
  .pipe(plugins.coffee, bare: true, sourceMap: !isProduction)
  .pipe(sourcemapsWrite)
  .pipe(gulp.dest, './build/assets/js')
  .pipe(plugins.notify, {onLast: true, message : 'Coffee compiled' })

gulp.task 'coffee', ->
  gulp.src(sources.coffee)
    .pipe(coffeePipe())

jsPipe = lazypipe()
  .pipe(gulp.dest, './build/assets/js')

gulp.task 'js', ->
  gulp.src(sources.js)
    .pipe(plugins.newer('./build/assets/js'))
    .pipe(jsPipe())

# gulp.task 'html', ->
#   gulp.src(sources.templates)
#     .pipe(htmlTplPipe())

dataPipe = ->
  gulp.src(sources.data)
    .pipe(hi())
    .map (file) ->
      json = yaml.safeLoad(file.contents.toString())
      name = path.basename(file.path, '.yml')
      [name, json]
    .reduce {}, (obj, [name, json]) ->
      obj[name] = json
      obj
    .flatMap (data) ->
      gulp.src(sources.slim)
        .pipe(plugins.slim {pretty: !isProduction, data: data})
        .pipe(hi())
    .pipe(gulp.dest('./build'))

gulp.task 'data', -> dataPipe()

gulp.task 'slim', ->
  dataPipe()
    .pipe(plugins.livereload())
    .pipe(plugins.notify({onLast: true, message : 'Slim compiled' }))

injection = ->
  cssSrc = ['./build/assets/styles/**/*.css']
  styles = gulp.src(cssSrc, read: false)
  js = gulp.src('./build/assets/js/**/*.js', read: false)
  bower = gulp.src(mainBowerFiles())
    .pipe(gulp.dest('./build/assets/vendor'))

  transformer = (p) ->
    p = path.relative('./build', p)
    switch path.extname(p)
      when '.js'
        "<script src=\"./#{p}\"></script>"
      when '.css'
        "<link rel=\"stylesheet\" href=\"./#{p}\">"

  gulp.src('./build/layout.html')
    .pipe(vinylPaths(del))
    .pipe(plugins.inject(bower, {
      starttag: '<!--inject:vendor:{{ext}}-->'
      endtag: '<!--endinject-->'
      addRootSlash: false
      transform: transformer
    }))

    .pipe(plugins.inject(es.merge(styles, js), {
      starttag: '<!--inject:{{ext}}-->'
      endtag: '<!--endinject-->'
      addRootSlash: false
      transform: transformer
    }))

    .pipe(plugins.rename('index.html'))
    .pipe(gulp.dest('./build'))

gulp.task 'inject', ['slim', 'coffee', 'js', 'less'], injection

gulp.task 'inject:js', ['slim', 'coffee', 'js'], injection
gulp.task 'inject:css', ['slim', 'less'], injection
gulp.task 'inject:bower', ['slim'], injection

imagesPipe = lazypipe()
  .pipe(gulp.dest, './build/images')

gulp.task 'images', ->
  gulp.src(sources.images)
    .pipe(plugins.newer './build/images')
    .pipe(imagesPipe())

gulp.task 'fonts', ->
  gulp.src(sources.fonts)
    .pipe(gulp.dest('./build/assets/fonts'))

gulp.task 'misc', ->
  gulp.src(sources.misc)
    .pipe(gulp.dest('./build'))

gulp.task 'clean', ->
  del [
    'build/**'
  ]
