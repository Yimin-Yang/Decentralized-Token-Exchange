pragma solidity ^0.4.13;


import "./owned.sol";
import "./FixedSupplyToken.sol";


contract Exchange is owned {

    ///////////////////////
    // GENERAL STRUCTURE //
    ///////////////////////
    struct Offer {

        uint amount;
        address who;
    }

    struct OrderBook {
        uint higherPrice;
        uint lowerPrice;

        mapping(uint => Offer) offers;
        uint offers_key;
        uint offers_length;
    }

    struct Token {

        address tokenContract;

        string symbolName;

        mapping(uint => OrderBook) buyBook;

        uint curBuyPrice;
        uint lowestBuyPrice;
        uint amountBuyPrices;

        mapping(uint => OrderBook) sellBook;
        uint curSellPrice;
        uint highestSellPrice;
        uint amountSellPrices;

    }


    //we support a max of 255 tokens...
    mapping(uint8 => Token) tokens;
    uint8 symbolNameIndex;


    //////////////
    // BALANCES //
    //////////////
    mapping(address => mapping(uint8 => uint)) tokenBalanceForAddress;

    mapping(address => uint) balanceEthForAddress;  //todo rename it to etherBalanceForAddress




    ////////////
    // EVENTS //
    ////////////


    //events for Deposit/Withdrawal
    event DepositForTokenReceived(address indexed _from, uint indexed _symbolIndex, uint _amount, uint _timestamp);
    event WithdrawalToken(address indexed _to, uint indexed _symbolIndex, uint _amount, uint _timestamp);
    event DepositForETHReceived(address indexed _from, uint amount, uint _timestamp);
    event WithdrawalETH(address indexed _to, uint _amount, uint _timestamp);


    //events for orders
    event LimitSellOrderCreated(uint indexed _symbolIndex, address indexed _who, uint _amountTokens, uint _priceInWei, uint _orderKey);
    event SellOrderFulfilled(uint indexed _symbolIndex, uint _amount, uint _priceInWei, uint _orderKey);
    event SellOrderCanceled(uint indexed _symbolIndex, uint _priceInWei, uint _orderKey);
    event LimitBuyOrderCreated(uint indexed _symbolIndex, address indexed _who, uint _amountTokens, uint _priceInWei, uint _orderKey);
    event BuyOrderFulfilled(uint indexed _symbolIndex, uint _amount, uint _priceInWei, uint _orderKey);
    event BuyOrderCanceled(uint indexed _symbolIndex, uint _priceInWei, uint _orderKey);

    //events for management
    event TokenAddedToSystem(uint _symbolIndex, string _token, uint _timestamp);



    //////////////////////////////////
    // DEPOSIT AND WITHDRAWAL ETHER //
    //////////////////////////////////
    function depositEther() payable {
        require(balanceEthForAddress[msg.sender] + msg.value >= balanceEthForAddress[msg.sender]);
        balanceEthForAddress[msg.sender] += msg.value;
        emit DepositForETHReceived(msg.sender, msg.value, now);
    }

    function withdrawEther(uint amountInWei) {
        require(balanceEthForAddress[msg.sender] - amountInWei >= 0);
        require(balanceEthForAddress[msg.sender] - amountInWei <= balanceEthForAddress[msg.sender]);
        balanceEthForAddress[msg.sender] -= amountInWei;
        msg.sender.transfer(amountInWei);
        emit WithdrawalETH(msg.sender, amountInWei, now);
    }

    function getEthBalanceInWei() constant returns (uint){
        return balanceEthForAddress[msg.sender];
    }


    //////////////////////
    // TOKEN MANAGEMENT //
    //////////////////////

    function addToken(string symbolName, address erc20TokenAddress) onlyowner {
        require(!hasToken(symbolName));
        symbolNameIndex++;
        tokens[symbolNameIndex].symbolName = symbolName;
        tokens[symbolNameIndex].tokenContract = erc20TokenAddress;
        emit TokenAddedToSystem(symbolNameIndex, symbolName, now);
    }

    function hasToken(string symbolName) constant returns (bool) {
        uint8 index = getSymbolIndex(symbolName);
        if (index == 0) {
            return false;
        }
        return true;
    }


    function getSymbolIndex(string symbolName) internal returns (uint8) {
        for (uint8 i = 1; i <= symbolNameIndex; i++) {
            if (stringsEqual(tokens[i].symbolName, symbolName)) {
                return i;
            }
        }
        return 0;
    }


    function getSymbolIndexOrThrow(string symbolName) returns (uint8) {
        uint8 index = getSymbolIndex(symbolName);
        require(index > 0);
        return index;
    }


    ////////////////////////////////
    // STRING COMPARISON FUNCTION //
    ////////////////////////////////
    function stringsEqual(string storage _a, string memory _b) internal returns (bool) {
        bytes storage a = bytes(_a);
        bytes memory b = bytes(_b);
        if (a.length != b.length) {
            return false;
        }
        for (uint i = 0; i < a.length; i++) {
            if (a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }


    //////////////////////////////////
    // DEPOSIT AND WITHDRAWAL TOKEN //
    //////////////////////////////////
    function depositToken(string symbolName, uint amount) {
        uint8 symbolNameIndex = getSymbolIndexOrThrow(symbolName);
        require(tokens[symbolNameIndex].tokenContract != address(0));

        ERC20Interface token = ERC20Interface(tokens[symbolNameIndex].tokenContract);

        require(token.transferFrom(msg.sender, address(this), amount));
        require(tokenBalanceForAddress[msg.sender][symbolNameIndex] + amount >= tokenBalanceForAddress[msg.sender][symbolNameIndex]);
        tokenBalanceForAddress[msg.sender][symbolNameIndex] += amount;
        emit DepositForTokenReceived(msg.sender, symbolNameIndex, amount, now);
    }


    function withdrawToken(string symbolName, uint amount) public {
        uint8 symbolNameIndex = getSymbolIndexOrThrow(symbolName);
        require(tokens[symbolNameIndex].tokenContract != address(0));

        ERC20Interface token = ERC20Interface(tokens[symbolNameIndex].tokenContract);

        require(tokenBalanceForAddress[msg.sender][symbolNameIndex] - amount >= 0);
        require(tokenBalanceForAddress[msg.sender][symbolNameIndex] - amount <= tokenBalanceForAddress[msg.sender][symbolNameIndex]);

        tokenBalanceForAddress[msg.sender][symbolNameIndex] -= amount;
        require(token.transfer(msg.sender, amount) == true);
        emit WithdrawalToken(msg.sender, symbolNameIndex, amount, now);
    }

    function getBalance(string symbolName) constant returns (uint) {
        uint8 symbolNameIndex = getSymbolIndexOrThrow(symbolName);
        return tokenBalanceForAddress[msg.sender][symbolNameIndex];
    }


    /////////////////////////////
    // ORDER BOOK - BID ORDERS //
    /////////////////////////////
    function getBuyOrderBook(string symbolName) constant returns (uint[], uint[]) {
        uint8 tokenNameIndex = getSymbolIndexOrThrow(symbolName);
        uint[] memory arrPricesBuy = new uint[](tokens[tokenNameIndex].amountBuyPrices);
        uint[] memory arrVolumesBuy = new uint[](tokens[tokenNameIndex].amountBuyPrices);

        uint whilePrice = tokens[tokenNameIndex].lowestBuyPrice;
        uint counter = 0;

        if (tokens[tokenNameIndex].curBuyPrice > 0) {
            while (whilePrice <= tokens[tokenNameIndex].curBuyPrice) {
                arrPricesBuy[counter] = whilePrice;
                uint volumeAtPrice = 0;
                uint offers_key = 0;

                offers_key = tokens[tokenNameIndex].buyBook[whilePrice].offers_key;
                while (offers_key <= tokens[tokenNameIndex].buyBook[whilePrice].offers_length) {
                    volumeAtPrice += tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].amount;
                    offers_key++;
                }
                arrVolumesBuy[counter] = volumeAtPrice;

                //next whilePrice
                if (whilePrice == tokens[tokenNameIndex].buyBook[whilePrice].higherPrice) {
                    break;
                } else {
                    whilePrice = tokens[tokenNameIndex].buyBook[whilePrice].higherPrice;
                }
                counter++;
            }
        }
        return (arrPricesBuy, arrVolumesBuy);
    }


    /////////////////////////////
    // ORDER BOOK - ASK ORDERS //
    /////////////////////////////
    function getSellOrderBook(string symbolName) constant returns (uint[], uint[]) {
        uint8 tokenNameIndex = getSymbolIndexOrThrow(symbolName);
        uint[] memory arrPricesSell = new uint[](tokens[tokenNameIndex].amountSellPrices);
        uint[] memory arrVolumesSell = new uint[](tokens[tokenNameIndex].amountSellPrices);
        uint sellWhilePrice = tokens[tokenNameIndex].curSellPrice;
        uint sellCounter = 0;
        if (tokens[tokenNameIndex].curSellPrice > 0) {
            while (sellWhilePrice <= tokens[tokenNameIndex].highestSellPrice) {
                arrPricesSell[sellCounter] = sellWhilePrice;
                uint sellVolumeAtPrice = 0;
                uint sell_offers_key = 0;

                sell_offers_key = tokens[tokenNameIndex].sellBook[sellWhilePrice].offers_key;
                while (sell_offers_key <= tokens[tokenNameIndex].sellBook[sellWhilePrice].offers_length) {
                    sellVolumeAtPrice += tokens[tokenNameIndex].sellBook[sellWhilePrice].offers[sell_offers_key].amount;
                    sell_offers_key++;
                }

                arrVolumesSell[sellCounter] = sellVolumeAtPrice;

                //next whilePrice
                if (tokens[tokenNameIndex].sellBook[sellWhilePrice].higherPrice == 0) {
                    break;
                }
                else {
                    sellWhilePrice = tokens[tokenNameIndex].sellBook[sellWhilePrice].higherPrice;
                }
                sellCounter++;

            }
        }
        return (arrPricesSell, arrVolumesSell);
    }



    ////////////////////////////
    // NEW ORDER - BID ORDER //
    ///////////////////////////
    function buyToken(string symbolName, uint priceInWei, uint amount) {
        uint8 tokenNameIndex = getSymbolIndexOrThrow(symbolName);
        uint total_amount_ether_necessary = 0;

        if (tokens[tokenNameIndex].amountSellPrices == 0 || tokens[tokenNameIndex].curSellPrice > priceInWei) {
            // if we have enough ether, we can buy that
            total_amount_ether_necessary = priceInWei * amount;

            //overflow check
            require(total_amount_ether_necessary > amount);
            require(total_amount_ether_necessary > priceInWei);
            require(balanceEthForAddress[msg.sender] >= total_amount_ether_necessary);
            require(balanceEthForAddress[msg.sender] - total_amount_ether_necessary >= 0);
            require(balanceEthForAddress[msg.sender] - total_amount_ether_necessary <= balanceEthForAddress[msg.sender]);

            // first deduct the amount of ether from our balance
            balanceEthForAddress[msg.sender] -= total_amount_ether_necessary;

            // limit order: we don't have enough offers to fulfill the amount

            // add the order to the orderBook
            addBuyOffer(tokenNameIndex, priceInWei, amount, msg.sender);

            // and emit the event
            emit LimitBuyOrderCreated(tokenNameIndex, msg.sender, amount, priceInWei, tokens[tokenNameIndex].buyBook[priceInWei].offers_length);

        } else {
            //market order: current sell price is smaller or equal to buy price!

            //1: find the "cheapest sell price" that is lower than the buy amount [buy:60@5000] [sell:50@4500] [sell:5@5000]
            //2: buy up the volume for 4500
            //3: buy up the volume for 5000
            //if still something remaining -> buyToken

            uint total_amount_ether_available = 0;
            uint whilePrice = tokens[tokenNameIndex].curSellPrice;
            uint amountNecessary = amount;
            uint offers_key;
            while (whilePrice <= priceInWei && amountNecessary > 0) {// start with the lowest sell price
                offers_key = tokens[tokenNameIndex].sellBook[whilePrice].offers_key;
                while (offers_key <= tokens[tokenNameIndex].sellBook[whilePrice].offers_length && amountNecessary > 0) {
                    uint volumeAtPriceFromAddress = tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].amount;

                    //Two choices from here:
                    //1) one person offers not enough volume to fulfill the market order - we use it up completely and move on to the next person who offers this token
                    //2) else: we make use of parts of what a person is offering - lower his amount, fulfill out order

                    if (volumeAtPriceFromAddress <= amountNecessary) {
                        total_amount_ether_available = whilePrice * volumeAtPriceFromAddress;

                        //overflow check
                        require(balanceEthForAddress[msg.sender] >= total_amount_ether_available);
                        require(balanceEthForAddress[msg.sender] - total_amount_ether_available <= balanceEthForAddress[msg.sender]);

                        //first deduct the amount of ether from our balance
                        balanceEthForAddress[msg.sender] -= total_amount_ether_available;

                        //overflow check
                        require(tokenBalanceForAddress[msg.sender][tokenNameIndex] + volumeAtPriceFromAddress >= tokenBalanceForAddress[msg.sender][tokenNameIndex]);
                        require(balanceEthForAddress[tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].who] + total_amount_ether_available >= balanceEthForAddress[tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].who]);

                        //this guy offers less or equal volume that we ask for, so we use it up completely
                        tokenBalanceForAddress[tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].who][tokenNameIndex] += volumeAtPriceFromAddress;
                        tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].amount = 0;
                        balanceEthForAddress[tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].who] += total_amount_ether_available;

                        tokens[tokenNameIndex].sellBook[whilePrice].offers_key++;
                        emit SellOrderFulfilled(tokenNameIndex, volumeAtPriceFromAddress, whilePrice, offers_key);

                        amountNecessary -= volumeAtPriceFromAddress;
                    } else {
                        require(volumeAtPriceFromAddress - amountNecessary > 0);

                        total_amount_ether_necessary = amountNecessary * whilePrice;

                        //overflow check
                        require(balanceEthForAddress[msg.sender] >= total_amount_ether_necessary);
                        require(balanceEthForAddress[msg.sender] - total_amount_ether_necessary <= balanceEthForAddress[msg.sender]);

                        //first deduct the amount of ether from our balance
                        balanceEthForAddress[msg.sender] -= total_amount_ether_necessary;

                        //overflow check
                        require(balanceEthForAddress[tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].who] + total_amount_ether_necessary >= balanceEthForAddress[tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].who]);

                        //this guy offers more than we ask for. We reduce his stack, add the tokens to us and the ether to him
                        tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].amount -= amountNecessary;
                        balanceEthForAddress[tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].who] += total_amount_ether_necessary;
                        tokenBalanceForAddress[msg.sender][tokenNameIndex] += amountNecessary;

                        // we have fulfilled our order
                        emit SellOrderFulfilled(tokenNameIndex, amountNecessary, whilePrice, offers_key);

                        amountNecessary = 0;
                    }

                    // if we have the last offer of that price, we have to set curBuyPrice lower
                    if (offers_key == tokens[tokenNameIndex].sellBook[whilePrice].offers_length
                    && tokens[tokenNameIndex].sellBook[whilePrice].offers[offers_key].amount == 0) {
                        tokens[tokenNameIndex].amountSellPrices--;

                        //next whilePrice
                        if (whilePrice == tokens[tokenNameIndex].sellBook[whilePrice].higherPrice
                        || tokens[tokenNameIndex].sellBook[whilePrice].higherPrice == 0) {
                            // we have reached the last price, no more sell orders
                            tokens[tokenNameIndex].curSellPrice = 0;
                        }
                        else {
                            tokens[tokenNameIndex].curSellPrice = tokens[tokenNameIndex].sellBook[whilePrice].higherPrice;
                            tokens[tokenNameIndex].sellBook[tokens[tokenNameIndex].sellBook[whilePrice].higherPrice].lowerPrice = 0;
                        }
                    }
                    offers_key++;
                }
                //we set the curSellPrice again, since then the volume is used up for a lower price the curSellPrice is set there
                whilePrice = tokens[tokenNameIndex].curSellPrice;
            }

            if (amountNecessary > 0) {
                buyToken(symbolName, priceInWei, amountNecessary);
            }
        }
    }


    ///////////////////////////
    // BID LIMIT ORDER LOGIC //
    ///////////////////////////
    function addBuyOffer(uint8 tokenIndex, uint priceInWei, uint amount, address who) {
        tokens[tokenIndex].buyBook[priceInWei].offers_length++;
        tokens[tokenIndex].buyBook[priceInWei].offers[tokens[tokenIndex].buyBook[priceInWei].offers_length] = Offer(amount, who);

        if (tokens[tokenIndex].buyBook[priceInWei].offers_length == 1) {
            tokens[tokenIndex].buyBook[priceInWei].offers_key = 1;
            //todo check here

            // we have a new buy order - increase the counter, so we can set the getOrderBook array later
            tokens[tokenIndex].amountBuyPrices++;

            //lowerPrice and higherPrice have to be set
            uint curBuyPrice = tokens[tokenIndex].curBuyPrice;

            uint lowestBuyPrice = tokens[tokenIndex].lowestBuyPrice;
            if (lowestBuyPrice == 0 || lowestBuyPrice > priceInWei) {
                if (curBuyPrice == 0) {
                    //there is no buy offer yet, insert the first one
                    tokens[tokenIndex].curBuyPrice = priceInWei;
                    tokens[tokenIndex].buyBook[priceInWei].higherPrice = priceInWei;
                    //todo ask about here
                    tokens[tokenIndex].buyBook[priceInWei].lowerPrice = 0;
                } else {
                    // or the lowest one
                    tokens[tokenIndex].buyBook[lowestBuyPrice].lowerPrice = priceInWei;
                    tokens[tokenIndex].buyBook[priceInWei].higherPrice = lowestBuyPrice;
                    tokens[tokenIndex].buyBook[priceInWei].lowerPrice = 0;
                }
                tokens[tokenIndex].lowestBuyPrice = priceInWei;
            }
            else if (curBuyPrice < priceInWei) {
                // the offer to buy is the highest one
                tokens[tokenIndex].buyBook[curBuyPrice].higherPrice = priceInWei;
                tokens[tokenIndex].buyBook[priceInWei].higherPrice = priceInWei;
                tokens[tokenIndex].buyBook[priceInWei].lowerPrice = curBuyPrice;
                tokens[tokenIndex].curBuyPrice = priceInWei;
            }
            else {
                // we are somewhere in the middle, we need to find the right spot first

                uint buyPrice = tokens[tokenIndex].curBuyPrice;
                bool weFoundIt = false;
                while (buyPrice > 0 && !weFoundIt) {
                    if (buyPrice < priceInWei && tokens[tokenIndex].buyBook[buyPrice].higherPrice > priceInWei) {
                        // set the new orderBook entry higher/lowerPrice first right
                        tokens[tokenIndex].buyBook[priceInWei].lowerPrice = buyPrice;
                        tokens[tokenIndex].buyBook[priceInWei].higherPrice = tokens[tokenIndex].buyBook[buyPrice].higherPrice;

                        //set the higherPrice's orderBook entry's lowerPrice to current price
                        tokens[tokenIndex].buyBook[tokens[tokenIndex].buyBook[buyPrice].higherPrice].lowerPrice = priceInWei;

                        //set the lowerPrice's orderBook entries higherPrice to the current price
                        tokens[tokenIndex].buyBook[buyPrice].higherPrice = priceInWei;

                        //set weFoundIt
                        weFoundIt = true;
                    }
                    buyPrice = tokens[tokenIndex].buyBook[buyPrice].lowerPrice;
                }
            }
        }
    }


    ////////////////////////////
    // NEW ORDER - ASK ORDER //
    ///////////////////////////
    function sellToken(string symbolName, uint priceInWei, uint amount) {
        uint8 tokenNameIndex = getSymbolIndexOrThrow(symbolName);
        uint total_amount_ether_necessary = 0;
        uint total_amount_ether_available = 0;

        // if we have enough ether, we can buy that
        total_amount_ether_necessary = priceInWei * amount;

        //overflow check
        require(total_amount_ether_necessary > amount);
        require(total_amount_ether_necessary > priceInWei);
        require(tokenBalanceForAddress[msg.sender][tokenNameIndex] >= amount);
        require(tokenBalanceForAddress[msg.sender][tokenNameIndex] - tokenNameIndex >= 0);
        require(balanceEthForAddress[msg.sender] + total_amount_ether_necessary >= balanceEthForAddress[msg.sender]);
        //todo change it to >

        // actually subtract the amount of tokens to change it then
        tokenBalanceForAddress[msg.sender][tokenNameIndex] -= amount;

        if (tokens[tokenNameIndex].amountBuyPrices == 0 || tokens[tokenNameIndex].curBuyPrice < priceInWei) {
            // limit order: we don't have enough offers to fulfill the amount

            // add the order to the orderBook
            addSellOffer(tokenNameIndex, priceInWei, amount, msg.sender);

            // and emit the event
            emit LimitSellOrderCreated(tokenNameIndex, msg.sender, amount, priceInWei, tokens[tokenNameIndex].buyBook[priceInWei].offers_length);

        } else {
            // market order: current buy price is bigger or equal to sell price!
            // 1.find the "highest buy price" that is higher than the sell amount
            // buy: 60@5000  buy: 50@4500  sell: 500@4000
            // 2. sell up the amount for 5000
            // 3. sell up the amount for 4500
            // if still something remaining -> sellToken limit order
            //
            // 2. sell up the volume
            // 2.1 add ether to seller, add symbolName to buyer until offers_key <= offers_length

            uint whilePrice = tokens[tokenNameIndex].curBuyPrice;
            uint amountNecessary = amount;
            uint offers_key;
            while (whilePrice >= priceInWei && amountNecessary > 0) {// start with the highest buy price
                offers_key = tokens[tokenNameIndex].buyBook[whilePrice].offers_key;
                while (offers_key <= tokens[tokenNameIndex].buyBook[whilePrice].offers_length && amountNecessary > 0) {
                    uint volumeAtPriceFromAddress = tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].amount;

                    //Two choices from here:
                    //1) one person offers not enough volume to fulfill the market order - we use it up completely and move on to the next person who offers this token
                    //2) else: we make use of parts of what a person is offering - lower his amount, fulfill out order

                    if (volumeAtPriceFromAddress <= amountNecessary) {
                        total_amount_ether_available = whilePrice * volumeAtPriceFromAddress;


                        //overflow check
                        require(tokenBalanceForAddress[msg.sender][tokenNameIndex] >= volumeAtPriceFromAddress);

                        //actually subtract the amount of tokens to change it then
                        tokenBalanceForAddress[msg.sender][tokenNameIndex] -= volumeAtPriceFromAddress;

                        //overflow check
                        require(tokenBalanceForAddress[tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].who][tokenNameIndex] + volumeAtPriceFromAddress >= tokenBalanceForAddress[tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].who][tokenNameIndex]);
                        require(balanceEthForAddress[msg.sender] + total_amount_ether_available >= balanceEthForAddress[msg.sender]);

                        //this guy offers less or equal volume that we ask for, so we use it up completely
                        tokenBalanceForAddress[tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].who][tokenNameIndex] += volumeAtPriceFromAddress;
                        tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].amount = 0;
                        balanceEthForAddress[msg.sender] += total_amount_ether_available;

                        //todo check tokenBalanceForAddress and balanceEthForAddress
                        tokens[tokenNameIndex].buyBook[whilePrice].offers_key++;
                        emit SellOrderFulfilled(tokenNameIndex, volumeAtPriceFromAddress, whilePrice, offers_key);

                        amountNecessary -= volumeAtPriceFromAddress;
                    } else {
                        require(volumeAtPriceFromAddress - amountNecessary > 0);

                        total_amount_ether_necessary = amountNecessary * whilePrice;

                        //overflow check
                        require(tokenBalanceForAddress[msg.sender][tokenNameIndex] >= amountNecessary);

                        //actually subtract the amount of tokens to change it then
                        tokenBalanceForAddress[msg.sender][tokenNameIndex] -= amountNecessary;

                        //overflow check
                        require(tokenBalanceForAddress[tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].who][tokenNameIndex] + amountNecessary >= tokenBalanceForAddress[tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].who][tokenNameIndex]);
                        require(balanceEthForAddress[msg.sender] + total_amount_ether_necessary >= balanceEthForAddress[msg.sender]);

                        //this guy offers more than we ask for. We reduce his stack, add the eth to us and the token to him

                        tokenBalanceForAddress[tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].who][tokenNameIndex] += amountNecessary;
                        tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].amount -= amountNecessary;
                        balanceEthForAddress[msg.sender] += total_amount_ether_necessary;

                        emit SellOrderFulfilled(tokenNameIndex, amountNecessary, whilePrice, offers_key);

                        amountNecessary = 0;
                        // we have fulfilled our order
                    }
                    if (offers_key == tokens[tokenNameIndex].buyBook[whilePrice].offers_length
                    && tokens[tokenNameIndex].buyBook[whilePrice].offers[offers_key].amount == 0) {
                        tokens[tokenNameIndex].amountBuyPrices--;

                        //next whilePrice
                        if (whilePrice == tokens[tokenNameIndex].buyBook[whilePrice].lowerPrice
                        || tokens[tokenNameIndex].buyBook[whilePrice].lowerPrice == 0) {// we have reached the last price
                            tokens[tokenNameIndex].curBuyPrice = 0;
                        }
                        else {
                            tokens[tokenNameIndex].curBuyPrice = tokens[tokenNameIndex].buyBook[whilePrice].lowerPrice;
                            tokens[tokenNameIndex].buyBook[tokens[tokenNameIndex].buyBook[whilePrice].lowerPrice].higherPrice = tokens[tokenNameIndex].curBuyPrice;
                        }

                    }
                    offers_key++;
                }
                //we set the curSellPrice again, since then the volume is used up for a lower price the curSellPrice is set there
                whilePrice = tokens[tokenNameIndex].curBuyPrice;
            }

            if (amountNecessary > 0) {
                sellToken(symbolName, priceInWei, amountNecessary);
            }
        }
    }


    ///////////////////////////
    // ASK LIMIT ORDER LOGIC //
    ///////////////////////////
    function addSellOffer(uint8 tokenIndex, uint priceInWei, uint amount, address who) {
        tokens[tokenIndex].sellBook[priceInWei].offers_length++;
        tokens[tokenIndex].sellBook[priceInWei].offers[tokens[tokenIndex].sellBook[priceInWei].offers_length] = Offer(amount, who);

        if (tokens[tokenIndex].sellBook[priceInWei].offers_length == 1) {
            tokens[tokenIndex].sellBook[priceInWei].offers_key = 1;
            //todo check here

            // we have a new sell order - increase the counter, so we can set the getOrderBook array later
            tokens[tokenIndex].amountSellPrices++;

            //lowerPrice and higherPrice have to be set
            uint curSellPrice = tokens[tokenIndex].curSellPrice;

            uint highestSellPrice = tokens[tokenIndex].highestSellPrice;
            if (highestSellPrice == 0 || highestSellPrice < priceInWei) {
                if (curSellPrice == 0) {
                    //there is no sell offer yet, insert the first one
                    tokens[tokenIndex].curSellPrice = priceInWei;
                    tokens[tokenIndex].sellBook[priceInWei].higherPrice = 0;
                    tokens[tokenIndex].sellBook[priceInWei].lowerPrice = 0;
                    //todo check here
                } else {
                    //this is the highest sell order
                    tokens[tokenIndex].sellBook[highestSellPrice].higherPrice = priceInWei;
                    tokens[tokenIndex].sellBook[priceInWei].lowerPrice = highestSellPrice;
                    tokens[tokenIndex].sellBook[priceInWei].higherPrice = 0;
                    //todo check here
                }
                tokens[tokenIndex].highestSellPrice = priceInWei;
            }
            else if (curSellPrice > priceInWei) {
                // the offer to sell is the lowest one
                tokens[tokenIndex].sellBook[curSellPrice].lowerPrice = priceInWei;
                tokens[tokenIndex].sellBook[priceInWei].higherPrice = curSellPrice;
                tokens[tokenIndex].sellBook[priceInWei].lowerPrice = 0;
                tokens[tokenIndex].curSellPrice = priceInWei;
            }
            else {
                // we are somewhere in the middle, we need to find the right spot first

                uint sellPrice = tokens[tokenIndex].curSellPrice;
                bool weFoundIt = false;
                while (sellPrice > 0 && !weFoundIt) {
                    if (sellPrice < priceInWei && tokens[tokenIndex].sellBook[sellPrice].higherPrice > priceInWei) {
                        // set the new orderBook entry higher/lowerPrice first right
                        tokens[tokenIndex].sellBook[priceInWei].lowerPrice = sellPrice;
                        tokens[tokenIndex].sellBook[priceInWei].higherPrice = tokens[tokenIndex].sellBook[sellPrice].higherPrice;

                        //set the higherPrice's orderBook entry's lowerPrice to current price
                        tokens[tokenIndex].sellBook[tokens[tokenIndex].sellBook[sellPrice].higherPrice].lowerPrice = priceInWei;

                        //set the lowerPrice's orderBook entries higherPrice to the current price
                        tokens[tokenIndex].sellBook[sellPrice].higherPrice = priceInWei;

                        //set weFoundIt
                        weFoundIt = true;
                    }
                    sellPrice = tokens[tokenIndex].sellBook[sellPrice].higherPrice;
                }
            }
        }
    }


    //////////////////////////////
    // CANCEL LIMIT ORDER LOGIC //
    //////////////////////////////
    function cancelOrder(string symbolName, bool isSellOrder, uint priceInWei, uint offerKey) {
        uint8 symbolNameIndex = getSymbolIndexOrThrow(symbolName);
        if (isSellOrder) {
            require(tokens[symbolNameIndex].sellBook[priceInWei].offers[offerKey].who == msg.sender);

            uint tokensAmount = tokens[symbolNameIndex].sellBook[priceInWei].offers[offerKey].amount;
            require(tokenBalanceForAddress[msg.sender][symbolNameIndex] + tokensAmount >= tokenBalanceForAddress[msg.sender][symbolNameIndex]);


            tokenBalanceForAddress[msg.sender][symbolNameIndex] += tokensAmount;
            tokens[symbolNameIndex].sellBook[priceInWei].offers[offerKey].amount = 0;
            emit SellOrderCanceled(symbolNameIndex, priceInWei, offerKey);

        }
        else {
            require(tokens[symbolNameIndex].buyBook[priceInWei].offers[offerKey].who == msg.sender);
            uint etherToRefund = tokens[symbolNameIndex].buyBook[priceInWei].offers[offerKey].amount * priceInWei;
            require(balanceEthForAddress[msg.sender] + etherToRefund >= balanceEthForAddress[msg.sender]);

            balanceEthForAddress[msg.sender] += etherToRefund;
            tokens[symbolNameIndex].buyBook[priceInWei].offers[offerKey].amount = 0;
            emit BuyOrderCanceled(symbolNameIndex, priceInWei, offerKey);
        }
    }
}
