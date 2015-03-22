# Gulp Utils
gulp = require 'gulp'
clean = require 'gulp-clean'
less = require 'gulp-less'
gutil = require 'gulp-util'
rename = require 'gulp-rename'
uglify = require 'gulp-uglify'
debug = require 'gulp-debug'
runSequence = require 'run-sequence'
sourcemaps = require 'gulp-sourcemaps'
buffer = require 'vinyl-buffer'
source = require 'vinyl-source-stream'
transform = require 'vinyl-transform'
zopfli = require 'gulp-zopfli'

# Development
browserSync = require 'browser-sync'
browserify = require 'browserify'
exorcist = require 'exorcist'
watchify = require 'watchify'

# Database
redis = require 'redis'

SITE_ID = 'something'

# Default gulp tasks watches files for changes
gulp.task "default", ['browser-sync'], ->
  gulp.watch "styles/*.less", ["styles", browserSync.reload]
  gulp.watch 'static/**', ['static', browserSync.reload]
  return

# For development.
gulp.task "browser-sync", ['compile-watch', 'styles', 'static'], ->
  browserSync
    proxy: "localhost:8088"
    logConnections: true
    injectChanges: true
  return

# WATCHIFY
opts = watchify.args
opts.extensions = ['.coffee', '.cjsx']
opts.debug = true
w = watchify browserify('./app/app.cjsx', opts)

gulp.task 'bundle', ->
  # Remove the sorted set (from Redis) that contains all valid compiled routes.
  red = redis.createClient()
  red.del 'rjsRoute.h.'+SITE_ID, (err, res) ->
    console.log 'expireHtml', err, res
    red.end()
  w.bundle()
    .on 'error', gutil.log.bind gutil, 'Browserify Error'
    .pipe source('app.js')
      .pipe buffer()
      .pipe(sourcemaps.init({loadMaps: true}))
      .pipe(sourcemaps.write('./'))
    .pipe gulp.dest('./public/assets')
    .pipe browserSync.reload({stream:true})

w.on 'update', () ->
  runSequence 'bundle'

gulp.task 'compile-watch', (cb) ->
  runSequence 'bundle', cb
  return
# /WATCHIFY

# Process LESS to CSS.
gulp.task 'styles', ->
  gulp.src(["styles/app.less", 'styles/print.less', 'styles/iefix.less'])
    .pipe less()
    .pipe gulp.dest("./public/assets")

# Copy static files.
gulp.task 'static', ->
  gulp.src('./static/**')
    .pipe gulp.dest('./public/')

# - - - - prod - - - -

gulp.task 'prod', ['prod_clean'], (cb) ->
  runSequence ['static'], ['compile', 'styles'], cb

# This generates the js app file.
gulp.task 'compile', ->
  browserified = transform (filename) ->
    b = browserify {debug: true, extensions: ['.cjsx', '.coffee']}
    b.add filename
    #b.transform 'coffee-reactify'
    b.bundle()
  gulp.src 'app/app.cjsx'
    .pipe browserified
    # Extract the map.
    .pipe transform(-> exorcist('./public/assets/app.js.map'))
    # Shrink the codebase.
    .pipe uglify()
    # Rename the file.
    .pipe rename('app.js')
    .pipe gulp.dest('./public/assets')
  # Remove the sorted set (from Redis) that contains all valid compiled routes.
  red.del 'rjsRoute.h.mica', (err, res) ->
    console.log 'expireHtml', err, res
    red.end()

# Remove contents from public directory.
gulp.task 'prod_clean', ->
  gulp.src('./public', read: false)
    .pipe(clean())


gulp.task 'deploy', ['prod'], ->
  gulp.src './public/**/*'
    .pipe deploy cacheDir: './tmp'

# Remove contents from prod directory.
gulp.task 'prod_clean', ->
  gulp.src('./prod', read: false)
    .pipe(clean())

gulp.task 'prod_static', ->
  gulp.src('./static/**')
    .pipe gulp.dest('./prod/')

gulp.task 'cssProd', ->
  runSequence ['copy_css', 'templatesProd']
  return

gulp.task 'copy_css', ['styles'], ->
  gulp.src('./dev/app.css')
    .pipe(rename(global.sha+'.css'))
    .pipe(gulp.dest('./prod'))
  gulp.src('./dev/print.css')
    .pipe(gulp.dest('./prod'))

gulp.task 'compress', ->
  gulp.src("./prod/*.{js,css,html,json}")
    .pipe(zopfli())
    .pipe(gulp.dest("./prod"))