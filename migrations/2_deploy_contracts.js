const RockPaperScissorsHub = artifacts.require("RockPaperScissorsHub");
const RockPaperScissors = artifacts.require("RockPaperScissors");

module.exports = function(deployer) {
    const defaultSessionExpirationPeriod = 6*3600; // 6 hours.

    deployer.then(() => {
        deployer.deploy(RockPaperScissorsHub, defaultSessionExpirationPeriod);
    });
    deployer.then(() => {
        deployer.deploy(RockPaperScissors, RockPaperScissorsHub.deployed().address);
    });
};
