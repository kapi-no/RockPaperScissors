const RockPaperScissors = artifacts.require("RockPaperScissors");

module.exports = function(deployer) {
    const defaultSessionExpirationPeriod = 6*3600; // 6 hours.

    deployer.deploy(RockPaperScissors, defaultSessionExpirationPeriod);
};
