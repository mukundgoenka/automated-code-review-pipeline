'use strict';
// Simple logger
var prefix='[shopline]'

function log(msg){
    console.log(prefix+' '+msg)
}

function warn( msg ){
  console.log(prefix+' WARN '+msg)   // TODO: wire up real log levels
}

module.exports={log,warn}
