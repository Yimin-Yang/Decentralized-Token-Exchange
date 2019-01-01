module.exports = {
    networks: {
        development: {
            host: "localhost",
            port: 8545,
            network_id: "*" // Match any network id
        },

        rinkeby: {
            host: "localhost",
            port: 8545,
            network_id: "4", // Rinkeby ID 4
            from: "0x8D56Be75cBbb56a809fCb24434b6d19e1a97AC7e",
            gas: 6500000,
            value: 0
        }
    }
};
