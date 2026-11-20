// The microphone worklet. It makes 16 kHz, 16-bit, mono PCM from the input,
// and posts one Int16Array each 200 ms. sampleRate is the rate of the context.
class LunaMic extends AudioWorkletProcessor {
  constructor() {
    super();
    this.step = sampleRate / 16000;
    this.sum = 0;
    this.count = 0;
    this.next = this.step;
    this.position = 0;
    this.out = new Int16Array(3200);
    this.length = 0;
  }

  process(inputs) {
    const input = inputs[0] && inputs[0][0];
    if (!input) return true;
    for (let i = 0; i < input.length; i++) {
      // The mean of the input samples for each output sample is a small low-pass filter.
      this.sum += input[i];
      this.count += 1;
      this.position += 1;
      if (this.position >= this.next) {
        const value = Math.max(-1, Math.min(1, this.sum / this.count));
        this.out[this.length++] = value < 0 ? value * 0x8000 : value * 0x7fff;
        this.sum = 0;
        this.count = 0;
        this.next += this.step;
        if (this.length === this.out.length) {
          this.port.postMessage(this.out.slice(0));
          this.length = 0;
        }
      }
    }
    return true;
  }
}

registerProcessor("luna-mic", LunaMic);
