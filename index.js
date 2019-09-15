const yargs = require("yargs");

const options = yargs
 .usage("Usage: -n <name>")
 .option("n", { alias: "name", describe: "Your name", type: "string", demandOption: true })
 .option("q", { alias: "second name", describe: "Your second name", type: "string", demandOption: true })
 .option("w", { alias: "last name", describe: "Your last name", type: "string", demandOption: true })
 .argv;

const greeting = `Hello, ${options.name}!`;

console.log(greeting);
