// Copyright 2014 Dartuino authors. Please see AUTHORS.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

library dartuino.mcu;

@MirrorsUsed(targets: 'Instruction')
import 'dart:mirrors';

import 'dart:typed_data';
import 'package:logging/logging.dart';

import 'clock.dart';

import 'src/memory.dart';
import 'src/program.dart';

import 'src/modules/interrupt_manager.dart';
import 'src/modules/timer.dart';

import 'src/misc/util.dart';
import 'src/misc/intel_hex.dart';

part 'src/instructions/instruction.dart';
part 'src/instructions/instructions_lookup.dart';

/**
 * ATmega328 implementation.
 */
class MCUnit {

  static final Logger log = new Logger('dartuino.mcu.MCUnit');

  // Status register flag/bit positions.
  static const STATUS_C = 0;
  static const STATUS_Z = 1;
  static const STATUS_N = 2;
  static const STATUS_V = 3;
  static const STATUS_S = 4;
  static const STATUS_H = 5;
  static const STATUS_T = 6;
  static const STATUS_I = 7;

  // Indirect registers addresses.
  static const INDIRECT_BASE = 26;
  static const INDIRECT_X = INDIRECT_BASE + 0;
  static const INDIRECT_Y = INDIRECT_BASE + 2;
  static const INDIRECT_Z = INDIRECT_BASE + 4;

  // Special registers addresses.
  static const SP_ADDRESS = 0x5D;
  static const STATUS_ADDRESS = 0x5F;

  static const PORTB_ADDRESS = 0x25;
  static const DDRB_ADDRESS = 0x24;
  static const PINB_ADDRESS = 0x23;

  static const PORTC_ADDRESS = 0x28;
  static const DDRC_ADDRESS = 0x27;
  static const PINC_ADDRESS = 0x26;

  static const PORTD_ADDRESS = 0x2B;
  static const DDRD_ADDRESS = 0x2A;
  static const PIND_ADDRESS = 0x29;

  static const SP_DEFAULT_VALUE = 0x900;
  static const MEMORY_SIZE = 2048;

  static const HIGH = 1;
  static const LOW = 0;

  /**
   * Program Counter Register.
   */
  int _pc;

  /**
   * Total executed cycles.
   */
  int totalCycles;

  /**
   * Number of cycles to wait until next instruction.
   */
  int waitCycles;

  /**
   * SRAM Storage.
   */
  Uint8List _memoryStorage;

  /**
   * Program Memory (Flash) storage.
   */
  Uint8List _flashStorage;

  /**
   * SRAM module.
   */
  Memory memory;

  /**
   * Flash memory (8 bit addresseable) module.
   */
  Memory flash;

  /**
   * Program memory (16 bit addresseable) module.
   */
  Program program;

  /**
   * General purpose registers memory module.
   */
  Memory registers;

  InterruptManager interruptManager;

  Timer0 timer0;

  Clock _clock;

  MCUnit.fromHex(String hexFile) {
    reset(hexFile);
  }

  /**
   * Connect read and write listeners to 16 bit selected [address].
   */
  void connect(address, {readListener, writeListener}) {
    memory.connect(address, read: readListener, write: writeListener);
  }

  /**
   * Reset the unit and loads a program (in Intel HEX format).
   */
  void reset(String hexFile) {

    _memoryStorage = new Uint8List(MEMORY_SIZE + SP_DEFAULT_VALUE);
    _flashStorage = parseIntelHex(hexFile);

    memory = new Memory(_memoryStorage);
    registers = new Memory(_memoryStorage);

    flash = new Memory(_flashStorage);
    program = new Program(new Uint16List.view(_flashStorage.buffer));

    timer0 = new Timer0(this);
    interruptManager = new InterruptManager();

    pc = 0;
    sp = SP_DEFAULT_VALUE - 1;

    status = 0;
    totalCycles = 0;
    waitCycles = 0;

  }

  /**
   * Get current opcode.
   */
  int getCurrentOpcode() => program[pc];

  /**
   * Get current instruction
   */
  Instruction getCurrentInstruction() => instructionsLookup[getCurrentOpcode()];

  /**
   * Runs a single instruction and execute pending interrupts taking care of the
   * cycles that must be spent.
   */
  void step() {

    bool interrupted = false;

    // Wait until there is no unspent cycle.
    if (waitCycles == 0) {

      var vector = null;
      logRegisters(this);

      if (i == HIGH) {

        vector = interruptManager.pendingInterrupts.indexOf(true);

        if (vector != null && vector != -1) {
          interrupted = true;
          waitCycles = 4;
        }

      }

      if (interrupted) {

        memory[sp--] = pc >> 8;
        memory[sp--] = pc & 0xFF;

        pc = ((vector) << 1);
        interruptManager.unregisterPending(vector * 2);

        i = LOW;

      } else {

        int opcode = getCurrentOpcode();

        Instruction instruction = getCurrentInstruction();
        pc = pc + 1;

        waitCycles = instruction.execute(this, opcode);

      }

    } else {

      log.finest('CPU WAIT...');

    }

    waitCycles--;
    totalCycles++;

  }

  int readStatus(int index) => getBit(status, index);
  writeStatus(int index, int value) => status = setBit(status, index, value);

  int get pc => _pc;

  set pc(int value) {
    _pc = value;
  }

  Clock get clock => _clock;

  void set clock(clock) {
    _clock = clock;
    _clock.register(this);
    _clock.register(this.timer0);
  }

  int get status => memory[STATUS_ADDRESS];
  set status(int value) => memory[STATUS_ADDRESS] = value;

  int get sp => memory.readWord(SP_ADDRESS);
  set sp(int value) => memory.writeWord(SP_ADDRESS, value);

  int get rx => registers.readWord(INDIRECT_X);
  set rx(int value) => registers.writeWord(INDIRECT_X, value);

  int get ry => registers.readWord(INDIRECT_Y);
  set ry(int value) => registers.writeWord(INDIRECT_Y, value);

  int get rz => registers.readWord(INDIRECT_Z);
  set rz(int value) => registers.writeWord(INDIRECT_Z, value);

  int get c => readStatus(STATUS_C);
  set c(int value) => writeStatus(STATUS_C, value);

  int get z => readStatus(STATUS_Z);
  set z(int value) => writeStatus(STATUS_Z, value);

  int get n => readStatus(STATUS_N);
  set n(int value) => writeStatus(STATUS_N, value);

  int get v => readStatus(STATUS_V);
  set v(int value) => writeStatus(STATUS_V, value);

  int get s => readStatus(STATUS_S);
  set s(int value) => writeStatus(STATUS_S, value);

  int get h => readStatus(STATUS_H);
  set h(int value) => writeStatus(STATUS_H, value);

  int get t => readStatus(STATUS_T);
  set t(int value) => writeStatus(STATUS_T, value);

  int get i => readStatus(STATUS_I);
  set i(int value) => writeStatus(STATUS_I, value);

}
