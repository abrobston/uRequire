# requires grunt 0.4.x
sourceDir     = "source/code"
buildDir      = "build/code"
sourceSpecDir = "source/spec"
buildSpecDir  = "build/spec"

gruntFunction = (grunt) ->
  _ = grunt.util._

  gruntConfig =
    pkg: grunt.file.readJSON('package.json')

    meta:
      banner: """
      /*!
      * <%= pkg.name %> - version <%= pkg.version %>
      * Compiled on <%= grunt.template.today(\"yyyy-mm-dd\") %>
      * <%= pkg.repository.url %>
      * Copyright(c) <%= grunt.template.today(\"yyyy\") %> <%= pkg.author.name %> (<%= pkg.author.email %> )
      * Licensed <%= pkg.licenses[0].type %> <%= pkg.licenses[0].url %>
      */\n
      """
      varVERSION: "var VERSION = '<%= pkg.version %>'; //injected by grunt:concat\n"
      mdVersion: "# <%= pkg.name %> v<%= pkg.version %>\n"
      usrBinEnvNode: "#!/usr/bin/env node\n"

    options: {sourceDir, buildDir, sourceSpecDir, buildSpecDir}

    copy:
      specResources:
        files: [
          expand: true
          cwd: "#{sourceSpecDir}/"
          src: ["*.json"]
          dest: "#{buildSpecDir}/"
        ]

      wiki:
        files: [
          expand: true
          cwd: "source/code/config/"
          src: ["*.coffee.md"]
          dest: "../uRequire.wiki/"
        ]

    concat:
      bin:
        options: banner: "<%= meta.usrBinEnvNode %><%= meta.banner %><%= meta.varVERSION %>"
        src: ['<%= options.buildDir %>/urequireCmd.js' ]
        dest: '<%= options.buildDir %>/urequireCmd.js'

      VERSIONurequire:
        options: banner: "<%= meta.banner %><%= meta.varVERSION %>"
        src: [ '<%= options.buildDir %>/urequire.js']
        dest:  '<%= options.buildDir %>/urequire.js'

    clean:
      build: [
        "<%= options.buildDir %>/**/*.*"
        "<%= options.buildSpecDir %>/**/*.*"
      ]

    watch:
      dev:
        files: ["#{sourceDir}/**/*.*", "#{sourceSpecDir}/**/*.*"]
        tasks: ['mocha']
      copyWiki:
        files: ["#{sourceDir}/**/*.*"]
        tasks: ['copy:wiki']

    shell:
      coffee: command: "coffee -cb -o ./#{buildDir} ./#{sourceDir}"
      coffeeSpec: command: "coffee -cb -o ./#{buildSpecDir} ./#{sourceSpecDir}"
      coffeeWatch: command: "coffee -cbw -o ./build ./source"
      chmod: command:
        if process.platform is 'linux' # change urequireCmd.js to executable - linux only
          "chmod +x 'build/code/urequireCmd.js'"
        else "@echo " #do nothing
      mocha: command: "mocha #{buildSpecDir} --recursive " # --reporter spec --bail
      doc: command: "codo source/code --title '<%= pkg.name %> v<%= pkg.version %> API documentation' --cautious"
      dev: command: "mocha #{sourceSpecDir} --recursive --compilers coffee:coffee-script --reporter spec"
#      draft: command: "coffee source/code/DRAFT.coffee"

      options: # subtasks inherit options but can override them
        verbose: true
        failOnError: true
        stdout: true
        stderr: true

  ### shortcuts generation ###
  splitTasks = (tasks)-> if !_.isString tasks then tasks else (_.filter tasks.split(' '), (v)-> v)

  grunt.registerTask cmd, splitTasks "shell:#{cmd}" for cmd of gruntConfig.shell # shortcut to all "shell:cmd"
  grunt.registerTask shortCut, splitTasks tasks for shortCut, tasks of {
     "default": "clean build chmod test"
     "build":   "shell:coffee concat copy:wiki"
     "test":    "shell:coffeeSpec copy:specResources mocha"

     # some shortcuts
     "cf":      "shell:coffee"
     "cfw":     "shell:coffeeWatch"

     # generic shortcuts
     "cl":      "clean"
     "b":       "build"
     "d":       "concat:bin chmod"
     "m":       "mocha"
     "t":       "test"

     # IDE shortcuts
     "alt-c": "copy:wiki"
     "alt-b": "b"
     "alt-d": "d"
     "alt-t": "t"
  }

  grunt.loadNpmTasks task for task in [
    'grunt-contrib-clean'
    'grunt-contrib-concat'
    'grunt-contrib-copy'
    'grunt-contrib-watch'
    'grunt-shell'
  ]

  grunt.initConfig gruntConfig

  null

module.exports = gruntFunction