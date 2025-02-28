import { execSync } from "child_process";
import * as fs from "fs";
import * as path from "path";

const chip32SimDir = "../../../../../chip32-sim";

const tests = [
  {
    name: "LoROM",
    filename: "roms/F-Zero.smc",
    expectedCore: 0,
  },
  {
    name: "HiROM",
    filename: "roms/Chrono Trigger.smc",
    expectedCore: 0,
  },
  {
    name: "ExHiROM",
    filename: "roms/Tales of Phantasia.smc",
    expectedCore: 0,
  },
  {
    name: "SPC7110",
    filename: "roms/Momotarou Dentetsu Happy (Japan).sfc",
    expectedCore: 1,
  },
  {
    name: "SDD1",
    filename: "roms/Star Ocean (Japan).sfc",
    expectedCore: 1,
  },
  // BSX isn't properly supported
  // {
  //   name: "BSX",
  //   filename: "roms/[ikari] Super Bomberman.bs",
  //   expectedCore: 1,
  // },
  {
    name: "PAL LoROM",
    filename: "roms/F-Zero (Europe).sfc",
    expectedCore: 2,
  },
];

const makeDataJson = (testCase) => {
  const filename = path.join(import.meta.dirname, testCase.filename);

  const contents = {
    data: {
      magic: "APF_VER_1",
      data_slots: [
        {
          name: "SMC",
          id: 0,
          filename,
          required: true,
          parameters: "0x109",
          extensions: ["smc", "sfc"],
          address: "0x10000000",
        },
      ],
    },
  };

  return JSON.stringify(contents, null, 2);
};

const printChip32Output = (json) => {
  console.log("Chip32 output:");
  console.log(`  Core: ${json.core}`);
  console.log(`  File state: ${json.file_state}`);
  console.log(`  Logs:`);
  const logs = json.logs.join("\n    ");
  console.log(`    ${logs}`);
};

const runTest = (testCase, testFilePath) => {
  console.log(`Running test: ${testCase.name} (File: ${testCase.filename})`);

  try {
    const loaderPinPath = path.join(import.meta.dirname, "../loader.bin");
    const stdout = execSync(
      `cargo run --quiet -- --data-json "${testFilePath}" --bin "${loaderPinPath}" --json`,
      { encoding: "utf8", cwd: chip32SimDir }
    );

    let jsonOutput;
    try {
      jsonOutput = JSON.parse(stdout);
    } catch (error) {
      console.error(`  ❌ Test failed: Invalid JSON output.\n${error}`);
      console.error("Stdout: ", stdout);
      return false;
    }

    if (jsonOutput.core !== testCase.expectedCore) {
      console.error(
        `  ❌ Test failed: Expected core ${testCase.expectedCore}, but got ${jsonOutput.core}`
      );
      printChip32Output(jsonOutput);
      return false;
    }
    if (jsonOutput.file_state === null || jsonOutput.file_state === undefined) {
      console.error(`  ❌ Test failed: file_state is null or undefined`);
      return false;
    }

    console.log(`  ✅ Test passed.\n`);
    return true;
  } catch (error) {
    console.error(`  ❌ Test failed: Command exited with code ${error.status}`);
    if (error.stderr) {
      console.error(`  Stderr:\n${error.stderr}`);
    }
    try {
      const jsonOutput = JSON.parse(error.stdout.toString());
      printChip32Output(jsonOutput);
    } catch {
      console.error("Stdout: ", error.stdout.toString());
    }

    console.log("\n");
    return false;
  }
};

const runAllTests = () => {
  let failCount = 0;

  if (!fs.existsSync("tmp")) {
    fs.mkdirSync("tmp");
  }

  for (const testCase of tests) {
    const singleTestFilePath = path.join(
      import.meta.dirname,
      "tmp",
      `test_roms_${testCase.name}.json`
    );
    fs.writeFileSync(singleTestFilePath, makeDataJson(testCase), "utf8");

    const passed = runTest(testCase, singleTestFilePath);
    if (!passed) {
      failCount += 1;
    }
  }

  if (failCount === 0) {
    console.log("\nAll tests passed!");
    return true;
  } else {
    console.error(`\n${failCount} tests failed!`);
    return false;
  }
};

let success = false;

try {
  success = runAllTests();
} finally {
  // fs.rmSync("tmp", { recursive: true, force: true });
}

if (!success) {
  process.exit(1);
}
