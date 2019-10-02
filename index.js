const os = require('os');
const util = require('util');
const path = require('path');
const execa = require('execa');
const macosVersion = require('macos-version');
const electronUtil = require('electron-util/node');
const debuglog = util.debuglog('capture');
const spawn = require('child_process').spawn

class ScreenCapture {
  constructor() {
    macosVersion.assertGreaterThanOrEqualTo('10.13');
  }

  startRecording({
    fps = 60,
    cropArea = undefined,
    showCursor = true,
    highlightClicks = false,
    screenId = 0,
    audioDeviceId = undefined,
    videoCodec = "h264"
  } = {}) {
    return new Promise((resolve, reject) => {
      if (this.recorder !== undefined) {
        reject(new Error('Call `.stopRecording()` first'));
        return;
      }

      if (highlightClicks === true) {
        showCursor = true;
      }

      if (typeof cropArea === 'object') {
        if (typeof cropArea.x !== 'number' ||
            typeof cropArea.y !== 'number' ||
            typeof cropArea.width !== 'number' ||
            typeof cropArea.height !== 'number') {
          reject(new Error('Invalid `cropArea` option object'));
          return;
        }
      }

      const recorderOpts = {
        framesPerSecond: fps,
        showCursor,
        highlightClicks,
        screenId,
        audioDeviceId
      };

      if (cropArea) {
        recorderOpts.cropRect = [
          [cropArea.x, cropArea.y],
          [cropArea.width, cropArea.height]
        ];
      }

      if (videoCodec) {
        const codecMap = new Map([
          ['h264', 'avc1'],
          ['hevc', 'hvc1'],
          ['proRes422', 'apcn'],
          ['proRes4444', 'ap4h']
        ]);

        if (!supportsHevcHardwareEncoding) {
          codecMap.delete('hevc');
        }

        if (!codecMap.has(videoCodec)) {
          throw new Error(`Unsupported video codec specified: ${videoCodec}`);
        }

        recorderOpts.videoCodec = codecMap.get(videoCodec);
      }

      var recorderOptsArgs = JSON.stringify(recorderOpts);
      console.log(recorderOptsArgs)
      this.recorder = spawn(BIN, [recorderOptsArgs]);
      const timeout = setTimeout(() => {
         if (this.recorder === undefined) {
           return;
         }

         const err = new Error('Could not start recording within 5 seconds');
         err.code = 'RECORDER_TIMEOUT';
         this.recorder.kill();
         delete this.recorder;
         reject(err);
      }, 5000);

      this.recorder.stdout.setEncoding('binary')
      this.recorder.stdout.on('data', function(chunk) {
         clearTimeout(timeout);
         console.log(chunk)
      })
                       
//      this.recorder.stdout.pipe(process.stdout)
                       
     this.recorder.stderr.on('data', function(data) {
        console.log('stderr: ' + data);
        clearTimeout(timeout);
        delete this.recorder;
        reject(error);
      });
     });
  }

  async stopRecording() {
    console.log("stop recording")
    this.recorder.kill();
    delete this.recorder;
  }
}

module.exports = () => new ScreenCapture();

module.exports.screens = async () => {
  const stderr = await execa.stderr(BIN, ['list-screens']);

  try {
    return JSON.parse(stderr);
  } catch (_) {
    return stderr;
  }
};

module.exports.audioDevices = async () => {
  const stderr = await execa.stderr(BIN, ['list-audio-devices']);

  try {
    return JSON.parse(stderr);
  } catch (_) {
    return stderr;
  }
};

Object.defineProperty(module.exports, 'videoCodecs', {
  get() {
    const codecs = new Map([
      ['h264', 'H264'],
      ['hevc', 'HEVC'],
      ['proRes422', 'Apple ProRes 422'],
      ['proRes4444', 'Apple ProRes 4444']
    ]);
    return codecs;
  }
});


// Workaround for https://github.com/electron/electron/issues/9459
const BIN = path.join(electronUtil.fixPathForAsarUnpack(__dirname), 'capture');

const supportsHevcHardwareEncoding = (() => {
  // Get the Intel Core generation, the `4` in `Intel(R) Core(TM) i7-4850HQ CPU @ 2.30GHz
  // More info: https://www.intel.com/content/www/us/en/processors/processor-numbers.html
  const result = /Intel.*Core.*i(?:7|5)-(\d)/.exec(os.cpus()[0].model);
  // Intel Core generation 6 or higher supports HEVC hardware encoding
  return result && Number(result[1]) >= 6;
})();
