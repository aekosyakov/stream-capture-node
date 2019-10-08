'use strict';
const delay = require('delay');
const capture = require('.');
const os = require('os');
const util = require('util');
const macosVersion = require('macos-version');
const electronUtil = require('electron-util/node');
const fs = require('fs');

async function main() {
  const recorder = capture();
  console.log('Screens:', await capture.screens());
  console.log('Audio devices:', await capture.audioDevices());
  console.log('Preparing to record for 5 seconds');
  await delay(1000);
  recorder.startRecording();
  console.log("start")
  await delay(50000);
  const fp = await recorder.stopRecording();
  fs.renameSync(fp, 'recording.mp4');
  console.log('Video saved in the current directory');
}

main().catch(console.error);

// Run: $ node example.js
