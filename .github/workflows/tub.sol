pragma solidity ^0.4.20;

import "ds-token/token.sol";

contract SptTub is DSMath, DSAuth {

    enum State { creating, working, stoped }
    State public state = State.creating;

    uint internal gem_mat_price = 0;

    uint public constant hedger_fee = 2 ether; //for per gem token

    ERC20 public usd_t;
    DSToken public gem_t;

    uint public accounts_gem_amount;
    uint public offers_usd_amount;

    uint internal col_usd_amount;// = 153 ether;

    uint public end_time;
    uint public ctrl_val_update_time = 0;
    uint public ctrl_val_max = 0;
    uint public ctrl_val_min = uint(-1);

    uint public ctrl_val_limit_max;
    uint public ctrl_val_limit_min;

    address oracle;

    struct HedgerOffer {
        address hedger;

        uint usd_amount;
        uint gem_price;
        uint min_perc;

        bool is_active;
    }
    HedgerOffer[] public offers;

    struct ClientAccount {
        address hedger;

        uint order_id;// только для удобства
        uint client_gem; //only for calc

        uint usd_amount; //client usd + hedger usd

        bool is_not_paid_to_hedger;
    }
    ClientAccount[] public accounts;

    mapping(address=>uint[]) public hedger_offers; // надо потом избавится, эту инфу брать из сообщений
    mapping(address=>uint[]) public hedger_accounts;   // надо потом избавится, эту инфу брать из сообщений

    modifier is_work() {require(state == State.working, ""); _;}
    modifier is_stoped() {require(state == State.stoped, ""); _;}
    modifier is_creating() {require(state == State.creating, ""); _;}

    constructor (ERC20 usd_token, address oracle_) public
    {
        require(address(usd_token) != address(0), "");
        require(oracle_ != address(0), "");

        usd_t = usd_token;
        oracle = oracle_;

        state = State.creating;
    }

    //------------------------------------ tmp function ----------------------------------
    function getHedgerOffers(address hedger) public view returns(uint[]) {return(hedger_offers[hedger]);}

    function getHedgerAccounts(address hedger) public view returns(uint[]) {return(hedger_accounts[hedger]);}

    //------------------------------------------------------------------------------------

    function getOffersCount() public view returns(uint) {return(offers.length);}

    function getAccountsCount() public view returns(uint) {return(accounts.length);}

    function createGemToken(string symbol_, string name_) public auth {
        gem_t = new DSToken(symbol_);
        require(gem_t != DSToken(0), "");

        gem_t.setName(name_);
    }

    function start(uint end_time_, uint limit_min, uint limit_max) public auth is_creating {
        require(end_time_ > 0, "");
        require(limit_min < limit_max, "");
        require(address(gem_t) != 0x00, "hasn't pai token address");
        require(col_usd_amount > 0, "col_usd_amount must be set");

        end_time = end_time_;
        ctrl_val_limit_max = limit_max;
        ctrl_val_limit_min = limit_min;

        state = State.working;
    }

    function stop() public auth is_work {
        //require(now > end_time, "");

        state = State.stoped;

        if(ctrl_val_update_time == 0) {
            setGemMatPrice(150 ether);
            return;
        }

        if(ctrl_val_max > ctrl_val_limit_max || ctrl_val_min < ctrl_val_limit_min) {
            setGemMatPrice(50 ether);
            return;
        }

        setGemMatPrice(150 ether);

    }

    function kill() public is_stoped auth {
        require(usd_t.transfer(owner, usd_t.balanceOf(address(this))), "");
        selfdestruct(owner);
    }

    function setControlValue(uint val_min, uint val_max, uint time_) public is_work {
        require(msg.sender == oracle, "");
        require(ctrl_val_update_time <= time_, "");
        require(val_max >= ctrl_val_max,"");
        require(val_min <= ctrl_val_min,"");


        ctrl_val_update_time = time_;

        if(ctrl_val_max != val_max) ctrl_val_max = val_max;

        if(ctrl_val_min != val_min) ctrl_val_min = val_min;


        if(time_ > end_time || ctrl_val_max > ctrl_val_limit_max || ctrl_val_min < ctrl_val_limit_min) {
            stop();
        }

    }

    function getGemCol() public view returns(uint usd_amount) {
        return getGemCol(1 ether);
    }

    function getGemCol(uint gem_amount) public view returns(uint usd_amount) {
        usd_amount = wmul(gem_amount, col_usd_amount);
    }

    function setGemCol(uint usd_amount) public is_creating auth {
        require(usd_amount > 0, "");

        col_usd_amount = usd_amount;
    }

    function getGemMatPrice() public view is_stoped returns(uint) {
        require(gem_mat_price != uint(0), "not set gem mat price");
        return gem_mat_price;
    }
    function setGemMatPrice(uint gem_mat_price_) public is_stoped auth returns(uint) {
        require(gem_mat_price_ != uint(0), "can't be zero");
        gem_mat_price = gem_mat_price_;
    }

//---------------------------------------------- client -------------------------------------------------------------

    function generateGem(uint usd_amount) public is_work returns(uint account_id) {

        uint offer_id;
        uint gem_price;
        uint gem_amount;
        (offer_id, gem_price, gem_amount) = getBestOffer(usd_amount);

        require(offer_id != uint(-1), "can't find hedger offer");

        require(usd_t.transferFrom(msg.sender, address(this), usd_amount), "can't transfer from client");

        offers[offer_id].is_active = false;

        account_id = accounts.length;

        accounts.push(ClientAccount(offers[offer_id].hedger,
                                    offer_id,
                                    gem_amount,
                                    add(usd_amount, offers[offer_id].usd_amount),
                                    true)
                    );

        gem_t.mint(msg.sender, gem_amount);

        accounts_gem_amount += gem_amount;
        offers_usd_amount = sub(offers_usd_amount, offers[offer_id].usd_amount);

        hedger_accounts[offers[offer_id].hedger].push(account_id);
    }

    function returnGem(uint gem_amount) public is_stoped {

        uint client_usd_amount = wmul(gem_amount, getGemMatPrice());

        accounts_gem_amount -= gem_amount;
        gem_t.burn(msg.sender, gem_amount);

        require(usd_t.transfer(msg.sender, client_usd_amount), "can't transfer to client");
    }

//---------------------------------------- hedger offers -------------------------------------------------------------

    function openHedgerOffer(uint usd_amount, uint gem_price, uint min_perc)
        public is_work returns(uint offer_id)
    {
        require(min_perc <= 1 ether, "");
        require(usd_amount > 0, "");

        require(usd_t.transferFrom(msg.sender, address(this), usd_amount), "can't transfer usd from hedger");

        offer_id = offers.length;
        offers.push(HedgerOffer(msg.sender, usd_amount, gem_price, min_perc, true));

        offers_usd_amount += usd_amount;

        hedger_offers[msg.sender].push(offer_id);
    }

    function changeHedgerOffer(uint offer_id, uint usd_amount, uint gem_price, uint min_perc)
        public is_work isOfferActiveAndOwner(offer_id)
    {
        require(min_perc <= 1 ether, "");
        require(usd_amount > 0, "");

        uint tmp_val;

        if(offers[offer_id].usd_amount < usd_amount) {
            tmp_val = usd_amount - offers[offer_id].usd_amount;

            require(usd_t.transferFrom(msg.sender, address(this), tmp_val), "");
            offers_usd_amount += tmp_val;
            offers[offer_id].usd_amount = usd_amount;
        }
        else if(offers[offer_id].usd_amount > usd_amount) {
            tmp_val = offers[offer_id].usd_amount - usd_amount;

            offers_usd_amount -= tmp_val;
            offers[offer_id].usd_amount = usd_amount;
            require(usd_t.transfer(msg.sender, tmp_val), "");
        }

        if(offers[offer_id].gem_price != gem_price) offers[offer_id].gem_price = gem_price;

        if(offers[offer_id].min_perc != min_perc) offers[offer_id].min_perc = min_perc;
    }

    function cancelHedgerOffer(uint offer_id) public isOfferActiveAndOwner(offer_id) {

         if(offers[offer_id].usd_amount > 0) {
            require(usd_t.transfer(msg.sender, offers[offer_id].usd_amount), "");
            offers_usd_amount -= offers[offer_id].usd_amount;
            offers[offer_id].usd_amount = 0;
        }

        offers[offer_id].is_active = false;
    }

//--------------------------------------- hedger accounts -------------------------------------------------------------

    function checkAccountCol(uint account_id) public view is_work returns(bool) {
        require(account_id < accounts.length, "");

        return checkCol(accounts[account_id].usd_amount, accounts[account_id].client_gem);
    }

    function addCollateral(uint account_id, uint usd_amount)
        public is_work isAccountActiveAndOwner(account_id)
    {
        require(usd_amount > 0, "");

        require(usd_t.transferFrom(msg.sender, address(this), usd_amount),"can't transfer usd from hefger");
        accounts[account_id].usd_amount = add(accounts[account_id].usd_amount, usd_amount);
    }

    function removeCollateral(uint account_id, uint usd_amount)
        public is_work isAccountActiveAndOwner(account_id)
    {
        require(usd_amount > 0, "");

        uint new_usd_amount = sub(accounts[account_id].usd_amount, usd_amount);

        require(checkCol(new_usd_amount, accounts[account_id].client_gem),
                "will't has enough collateral after remove");

        accounts[account_id].usd_amount = new_usd_amount;

        if(usd_amount > 0) require(usd_t.transfer(msg.sender, usd_amount),"");
    }

    function getHedgerPayout(uint account_id) public is_stoped isAccountActiveAndOwner(account_id) {

        uint client_depo = wmul(accounts[account_id].client_gem, getGemMatPrice());
        uint hedger_pay = sub(accounts[account_id].usd_amount, client_depo);

        uint hedger_usd_fee = wmul(accounts[account_id].client_gem, hedger_fee);

        require(usd_t.transferFrom(msg.sender,address(this), hedger_usd_fee), "can't transfer fee from hedger");

        require(usd_t.transfer(msg.sender, hedger_pay), "");

        accounts[account_id].is_not_paid_to_hedger = false;
    }

//----------------------------------------------------------------------------------------------------------

    modifier isOfferActiveAndOwner(uint offer_id) {
        require(offer_id < offers.length, "");
        require(offers[offer_id].is_active, "");
        require(offers[offer_id].hedger == msg.sender, "");
        _;
    }
    modifier isAccountActiveAndOwner(uint account_id) {
        require(account_id < accounts.length, "");
        require(accounts[account_id].is_not_paid_to_hedger, "");
        require(accounts[account_id].hedger == msg.sender, "");
        _;
    }

    function getBestOffer(uint client_usd)
        public view returns(uint offer_id_, uint gem_price_, uint gem_amount_)
    {
        offer_id_ = uint(-1);
        gem_price_ = uint(-1);
        gem_amount_ = 0;

        for(uint i = 0; i < offers.length; i++) {
            if(!offers[i].is_active) continue;

            if(!checkOffer(client_usd,
                            offers[i].usd_amount,
                            offers[i].gem_price,
                            offers[i].min_perc)
                ) continue;

            if(offers[i].gem_price < gem_price_ ) {
                offer_id_ = i;
                gem_price_ = offers[i].gem_price;
            }
        }

        if(offer_id_ != uint(-1))
            gem_amount_ = wdiv(client_usd, gem_price_);
    }

    function checkOffer(uint client_usd, uint offer_usd, uint gem_price, uint offer_min_perc)
        public view returns(bool)
    {
        if(!checkGemPrice(gem_price)) return false;

        uint gem_amount = wdiv(client_usd, gem_price);

        uint col_usd = getGemCol(gem_amount);

        if(add(client_usd, offer_usd) < col_usd) return false;

        //вроде не надо, но пусть пока будет
        if(client_usd >= col_usd) return false;

        return(wdiv(sub(col_usd, client_usd), offer_usd) >= offer_min_perc);
    }

    function checkGemPrice(uint gem_price) internal view returns(bool) {
        return (gem_price < getGemCol());
    }

    function checkCol(uint usd_amount, uint gem_amount) internal view returns(bool) {
        return (usd_amount >= getGemCol(gem_amount));
    }
}
