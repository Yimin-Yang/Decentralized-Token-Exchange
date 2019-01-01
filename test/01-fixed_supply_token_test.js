var fixedSupplyToken = artifacts.require("./FixedSupplyToken.sol");

contract('MyToken', function (accounts) {
    it("first account should own all tokens", function () {
        var _totalSupply;
        var myTokenInstance;
        return fixedSupplyToken.deployed().then(function (instance) {
            myTokenInstance = instance;
            return myTokenInstance.totalSupply.call();
        }).then(function (totalSupply) {
            _totalSupply = totalSupply;
            return myTokenInstance.balanceOf(accounts[0]);
        }).then(function (balanceAccountOwner) {
            assert.equal(balanceAccountOwner.toNumber(), _totalSupply.toNumber(), "Total Amount of tokens is owned by owner");
        });
    });

    it("second account should own no tokens", function () {
        var myTokenInstance;
        return fixedSupplyToken.deployed().then(function (instance) {
            myTokenInstance = instance;
            return myTokenInstance.balanceOf(accounts[1]);
        }).then(function (balanceAccountOwner) {
            assert.equal(balanceAccountOwner.toNumber(), 0, "Total Amount of tokens is owned by some other address");
        });
    });


    it("should send token correctly", function () {
        var token;

        // Get initial balances of first and second account
        var account1 = accounts[0];
        var account2 = accounts[1];

        var account1_starting_balance;
        var account2_starting_balance;

        var account1_ending_balance;
        var account2_ending_balance;

        var amount = 10;

        return fixedSupplyToken.deployed().then(function (instance) {
            token = instance;
            return token.balanceOf.call(account1);
        }).then(function (balance) {
            account1_starting_balance = balance.toNumber();
            return token.balanceOf.call(account2);
        }).then(function (balance) {
            account2_starting_balance = balance.toNumber();
            return token.transfer(account2, amount, {from: account1});
        }).then(function () {
            return token.balanceOf.call(account1);
        }).then(function (balance) {
            account1_ending_balance = balance.toNumber();
            return token.balanceOf.call(account2);
        }).then(function (balance) {
            account2_ending_balance = balance.toNumber();
            assert.equal(account1_ending_balance, account1_starting_balance - amount, "Amount wasn't correctly taken from the sender");
            assert.equal(account2_ending_balance, account2_starting_balance + amount, "Amount wasn't correctly sent to the receiver");
        })
    });

});