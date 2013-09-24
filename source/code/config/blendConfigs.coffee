_ = require 'lodash'
fs = require 'fs'
require('butter-require')() # no need to store it somewhere
_B = require 'uberscore'
l = new _B.Logger 'urequire/blendConfigs'

upath = require '../paths/upath'
MasterDefaultsConfig = require './MasterDefaultsConfig'
ResourceConverter = require './ResourceConverter'

UError = require '../utils/UError'

arrayizeUniquePusher = new _B.ArrayizePushBlender [], unique: true
arrayizePusher = new _B.ArrayizePushBlender

# Copy/clone all keys from the 'root' of src,
# to either `dst.bundle` or `dst.build` (the legitimate parts of the config),
# depending on where these keys appear in MasterDefaultsConfig.
#
# NOTE: it simply ignores unknown keys (i.e keys not in MasterDefaultsConfig .build or .bundle)
#       including 'derive'

moveKeysBlender = new _B.Blender [
  {
    order: ['path']
    '*': '|':
      do (partsKeys = {
        bundle: _.keys MasterDefaultsConfig.bundle # eg ['path', 'dependencies', ...]
        build: _.keys MasterDefaultsConfig.build   # eg ['dstPath', 'template', ...]
      })->
        (prop, src, dst)->
          for confPart in _.keys partsKeys # partKeys = ['bundle', 'build'] 
            if prop in partsKeys[confPart]
              _B.setp @dstRoot, "/#{confPart}/#{prop}", src[prop], overwrite:true
              break

          @SKIP # no assign

    # just DeepClone our 'legitimate' parts
    bundle: '|': -> _B.Blender.NEXT
    build: '|': -> _B.Blender.NEXT
  }
#  compilers: '|': -> _B.Blender.NEXT # @todo: how do we blend this ?
]

# Backwards compatibility:
# rename DEPRACATED keys to their new ones
renameKeys =
  $:
    bundle:
       bundlePath: 'path'
       bundleName: 'name'
       copyNonResources: 'copy'
       filespecs: 'filez'
       dependencies:
         noWeb: 'node'
         bundleExports: 'exports.bundle'
         variableNames: 'depsVars'
         _knownVariableNames: '_knownDepsVars'
    build:
      outputPath: 'dstPath'

_.extend renameKeys.$, renameKeys.$.bundle # copy $.bundle.* to $.*
_.extend renameKeys.$, renameKeys.$.build # copy $.build.* to $.*

depracatedKeysBlender = new _B.DeepDefaultsBlender [
  order:['src']
  '*': (prop, src, dst)->
    renameTo = _B.getp renameKeys, @path
    if  _.isString renameTo
      l.warn "DEPRACATED key '#{_.last @path}' found @ config path '#{@path.join '.'}' - rename to '#{renameTo}'"
      _B.setp @dstRoot, @path.slice(1,-1).join('.')+'.'+renameTo, src[prop], {overwrite:true, separator:'.'}
      return @SKIP

    @NEXT
]

addIgnoreToFilezAsExclude = (cfg)->
  ignore = _B.arrayize(cfg.bundle?.ignore || cfg.ignore)

  if not _.isEmpty ignore
    l.warn "DEPRACATED key 'ignore' found @ config - adding them as exclude '!' to 'bundle.filez'"
    filez = _B.arrayize(cfg.bundle?.filez || cfg.filez || ['**/*.*'])
    for ignoreSpec in ignore
      filez.push '!'
      filez.push ignoreSpec
    delete cfg.ignore
    delete cfg.bundle.ignore
    _B.setp cfg, ['bundle', 'filez'], filez, {overwrite:true}

  cfg

# The top level Blender, it uses 'path' to make decisions on how to blend `bundle`.
#
# It extends DeepCloneBlender, so if there's no path match,
# it works like _.clone (deeply).
{_optimizers} = MasterDefaultsConfig.build

bundleBuildBlender = new _B.DeepCloneBlender [
  {
    order: ['path', 'src']

    bundle:

      filez: '|' : '*': (prop, src, dst)-> arrayizePusher.blend dst[prop], src[prop]

      copy: '|' : '*': (prop, src, dst)-> arrayizePusher.blend dst[prop], src[prop]

      resources: '|' : '*': (prop, src, dst)->
        rcs = []
        for rc in src[prop]
          if _.isEqual rc, [null] # cater for [null] reset array signpost for arrayizePusher
            rcs.push rc
          else
            rc = ResourceConverter.register rc
            if rc and !_.isEmpty(rc)
              rcs.push rc

        arrayizePusher.blend dst[prop], rcs

      dependencies:

        node: '|': '*': (prop, src, dst)-> arrayizeUniquePusher.blend dst[prop], src[prop]

        exports:

          bundle: '|': '*': 'dependenciesBindings'

          root: '|': '*': (prop, src)-> src[prop]

        replace: '|': '*': 'dependenciesBindings' # paradoxically, its compatible albeit a different meaning!

        depsVars: '|': '*': 'dependenciesBindings'

        _knownDepsVars: '|': '*': 'dependenciesBindings'

    dependenciesBindings: (prop, src, dst)->
      dependenciesBindingsBlender.blend dst[prop], src[prop]

    build:

      template: '|': '*': (prop, src, dst)->
        templateBlender.blend dst[prop], src[prop]

      # 'optimize' ? in 3 different ways
      # todo: spec it
      optimize: '|':
        # enable 'uglify2' for true
        Boolean: (prop, src, dst)-> _optimizers[0] if src[prop]

        # find if proper optimizer, default 'ulgify2''
        String: (prop, src, dst)->
          if not optimizer = (_.find _optimizers, (v)-> v is src[prop])
            l.er "Unknown optimize '#{src[prop]}' - using 'uglify2' as default"
            _optimizers[0]
          else
            optimizer

        # eg optimize: { uglify2: {...uglify2 options...}}
        Object: (prop, src, dst)->
          # find a key that's an optimizer, eg 'uglify2'
          if not optimizer = (_.find _optimizers, (v)-> v in _.keys src[prop])
            l.er "Unknown optimize object", src[prop], " - using 'uglify2' as default"
            _optimizers[0]
          else 
            dst[optimizer] = src[prop][optimizer] # if optimizer is 'uglify2', copy { uglify2: {...uglify2 options...}} to dst ('ie build')
            optimizer
  }
]

###
*dependenciesBindingsBlender*

Converts String, Array<String> or Object {variable:bindingsArrayOfStringsOrString
to the 'proper' dependenciesBinding structure ({dependency1:ArrayOfDep1Bindings, dependency2:ArrayOfDep2Bindings, ...}

So with    *source*                 is converted to proper      *destination*
* String : `'lodash'`                       --->                `{lodash:[]}`

* Array<String>: `['lodash', 'jquery']`     --->            `{lodash:[], jquery:[]}`

* Object: `{lodash:['_'], jquery: '$'}`     --->          as is @todo: convert '$' to proper ['$'], i.e `{lodash:['_'], jquery: ['$']}`

The resulting array of bindings for each 'variable' is blended via arrayizeUniquePusher
to the existing? corresponding array on the destination
###
dependenciesBindingsBlender = new _B.DeepCloneBlender [
  order: ['src']                                                     # our src[prop] (i.e. depsVars eg exports.bundle) is either a:

  'String': (prop, src, dst)->                                       # String eg  'lodash', convert to {'lodash':[]}
    dst[prop] or= {}
    dst[prop][src[prop]] or= []                                      # set a 'lodash' key with `[]` as value on our dst
    dst[prop]

  'Array': (prop, src, dst)->                                        # Array, eg  `['lodash', 'jquery']`, convert to `{lodash:[], jquery:[]}`
    if not _.isPlainObject dst[prop]
      dst[prop] = {} # dependenciesBindingsBlender.blend {}, dst[prop] @todo: why call with 'jquery' returns { j: [] }, '1': { q: [] }, '2': { u: [] }, ....}
    else
      _B.mutate dst[prop], _B.arrayize

    for dep in src[prop]
      dst[prop][dep] = _B.arrayize dst[prop][dep]

    dst[prop]

  'Object': (prop, src, dst)->                                       # * Object eg {'lodash': '???', ...}, convert to    `{lodash:['???'], ...}`
    if not _.isPlainObject dst[prop]
      dst[prop] = {} # dependenciesBindingsBlender.blend {}, dst[prop] @todo: why call with 'jquery' returns { j: [] }, '1': { q: [] }, '2': { u: [] }, ....}
    else
      _B.mutate dst[prop], _B.arrayize

    for dep, depVars of src[prop]
      dst[prop][dep] = arrayizeUniquePusher.blend dst[prop][dep], depVars

    dst[prop]
]

deepCloneBlender = new _B.DeepCloneBlender #@todo: why deepCloneBlender need this instead of @

templateBlender = new _B.DeepCloneBlender [
  order: ['src']

  # our src[prop] template is a String eg 'UMD'.
  # blend as {name:'UMD'}
  'String': (prop, src, dst)->
    dst[prop] = {} if src[prop] isnt dst[prop]?.name
    deepCloneBlender.blend dst[prop], {name: src[prop]}

  # our src[prop] template is an Object - should be {name: 'UMD', '...': '...'}
  # blend as is but reset dst object if template has changed!
  'Object': 'templateSetter'

  templateSetter: (prop, src, dst)->
    dst[prop] = {} if (src[prop].name isnt dst[prop]?.name) and
                    not _.isUndefined(src[prop].name)
    deepCloneBlender.blend dst[prop], src[prop]
]

#create a finalCfg object & a default deriveLoader
# and call the recursive _blendDerivedConfigs
blendConfigs = (configsArray, deriveLoader)->
  finalCfg = {}

  deriveLoader = # default deriveLoader
    if _.isFunction deriveLoader
      deriveLoader
    else
      (derive)-> #default deriveLoader
        if _.isString derive
          l.debug "Loading config file: '#{derive}'"
          if cfgObject = require fs.realpathSync derive # @todo: test require using butter-require within uRequire :-)
            return cfgObject
        else
          if _.isObject derive
            return derive

        # if its hasnt returned, we're in error
        l.er """
          Error loading configuration files:
            derive """, derive, """ is a not a valid filename
            while processing derive array ['#{derive.join "', '"}']"
          """

  _blendDerivedConfigs finalCfg, configsArray, deriveLoader
  finalCfg

# the recursive fn that also considers cfg.derive
_blendDerivedConfigs = (cfgDest, cfgsArray, deriveLoader)->
  # We always blend in reverse order: start copying all items in the most base config
  # (usually 'MasterDefaultsConfig') and continue overwritting/blending backwards
  # from most general to the more specific. Hence the 1st item in configsArray is blended last.
  for cfg in cfgsArray by -1 when cfg

    # in each cfg, we might have nested `derive`s
    # recurse for each of those, depth first style - i.e we apply current cfg LAST
    # (and AFTER we have visited the furthest `derive`d config which has been applied first)
    derivedObjects =
      (for drv in _B.arrayize cfg.derive when drv # no nulls/empty strings
        deriveLoader drv)

    if not _.isEmpty derivedObjects
      _blendDerivedConfigs cfgDest, derivedObjects, deriveLoader

    # blend this cfg into cfgDest using the top level blender
    # first moveKeys for each config for configsArray items
    # @todo: (2, 7, 5) rewrite more functional, decoration/declarative/flow style ?
    bundleBuildBlender.blend cfgDest, moveKeysBlender.blend addIgnoreToFilezAsExclude depracatedKeysBlender.blend cfg
  null

# expose blender instances to module.exports/blendConfigs, mainly for testing
_.extend blendConfigs, {
  moveKeysBlender
  depracatedKeysBlender
  templateBlender
  dependenciesBindingsBlender
  bundleBuildBlender
}

module.exports = blendConfigs
