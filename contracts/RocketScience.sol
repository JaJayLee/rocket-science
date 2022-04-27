// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6;

import "./Ownable.sol";

enum WithdrawalType {
    EARNED,
    REFERRALS
}

struct Packet {
    uint256 id;
    uint256 startTime;
    uint256 finishTime;
    uint256 paid;
    uint256 invested;
}

struct Investor {
    address referrer;
    uint256 totalInvested;
    uint256 earned;
    uint256 refReward;
    uint256 refs;
}

struct Withdrawal {
    uint256 amount;
    uint256 timestamp;
    WithdrawalType t;
}

struct ReferralReward {
    address user;
    uint256 amount;
    uint256 timestamp;
}



contract RocketScience is Ownable {

    uint256 public constant PACKET_LIFETIME = 15 days;
    uint256 public constant DAY = 1 days;
    uint256 public constant REFERRAL_PERCENTAGE = 10;
    uint256 public constant TOTAL_REWARD = 225;
    uint256 public constant PERCENTAGE_OF_OWNER_REWARD = 10;

    uint256 public constant DAILY_REWARD = 15; // %

    uint256 public totalInvest;
    uint256 public totalInvestors;

    mapping(address => Investor) public investors;
    mapping(address => mapping(uint256 => uint256)) lastUpdate;

    mapping(address => uint256) public refRewards;

    mapping(address => Withdrawal[]) withdrawals;
    mapping(address => ReferralReward[]) referralsRewards;

    mapping(address => mapping(address => bool)) referrals;

    mapping(address => Packet[]) userPackets;
    mapping(address => uint256) packetNumbers;

    fallback() external payable{
        sendValue(payable(msg.sender), msg.value);
    }

    constructor() {
        Investor memory _investorOwner;
        _investorOwner.referrer = address(this);

        investors[owner()] = _investorOwner;
        totalInvestors++;
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function invest() external payable {
        require(
            msg.value >= 1e16 &&
                msg.value <= 1e21,
            "Wrong amount"
        );

        uint256 _packetId = packetNumbers[msg.sender];

        uint256 _earn = msg.value * REFERRAL_PERCENTAGE / 100;

        address _referrer = investors[msg.sender].referrer;
        if (_referrer != address(0)) {
            _update(msg.sender, _referrer, _earn);
        } else {
            investors[msg.sender].referrer = owner();
            totalInvestors++;

            _update(msg.sender, owner(), _earn);
        }

        investors[msg.sender].totalInvested += msg.value;
        lastUpdate[msg.sender][_packetId] = block.timestamp;

        Packet memory _packet = Packet({
            id: _packetId,
            startTime: block.timestamp,
            finishTime: block.timestamp + PACKET_LIFETIME,
            invested: msg.value,
            paid: 0
        });

        userPackets[msg.sender].push(_packet);

        packetNumbers[msg.sender]++;
        totalInvest += msg.value;
        sendValue(payable(owner()), msg.value / PERCENTAGE_OF_OWNER_REWARD);
    }

    function _update(
        address _user,
        address _referrer,
        uint256 _amount
    ) internal {
        if (_amount > 0) {
            ReferralReward memory _newReferralReward = ReferralReward({
                user: _user,
                amount: _amount,
                timestamp: block.timestamp
            });

            refRewards[_referrer] += _amount;
            investors[_referrer].refReward += _amount;
            referralsRewards[_referrer].push(_newReferralReward);

            if (!referrals[_referrer][_user]) {
                referrals[_referrer][_user] = true;
                investors[_referrer].refs++;
            }
        }
    }

    function investByRef(address _referrer) external payable {
        require(msg.sender != _referrer, "You can't invest to yourself");
        require(
            msg.value >= 1e16 &&
                msg.value <= 1e21,
            "Wrong amount"
        );
        require(_referrer != address(0), "Referrer can not be a null address");

        if (investors[msg.sender].referrer == address(0)) {
            investors[msg.sender].referrer = _referrer;
            totalInvestors++;
        }
        else _referrer = investors[msg.sender].referrer;

        uint256 _packetId = packetNumbers[msg.sender];
        uint256 _earn = msg.value * REFERRAL_PERCENTAGE / 100;
        _update(msg.sender, _referrer, _earn);

        investors[msg.sender].totalInvested += msg.value;

        lastUpdate[msg.sender][_packetId] = block.timestamp;

        Packet memory _packet = Packet({
            id: _packetId,
            startTime: block.timestamp,
            finishTime: block.timestamp + PACKET_LIFETIME,
            invested: msg.value,
            paid: 0
        });

        userPackets[msg.sender].push(_packet);

        packetNumbers[msg.sender]++;

        totalInvest += msg.value;
        sendValue(payable(owner()), msg.value / PERCENTAGE_OF_OWNER_REWARD);
    }

    function takeInvestment(uint256 _packetId) external {
        require(packetNumbers[msg.sender] > _packetId, "Packet doesn't exist");

        uint256 _earned = totalClaimable(_packetId, msg.sender);

        lastUpdate[msg.sender][_packetId] = block.timestamp;
        investors[msg.sender].earned += _earned;

        userPackets[msg.sender][_packetId].paid += _earned;

        sendValue(payable(msg.sender), _earned);

        Withdrawal memory _withdrawal = Withdrawal({
            amount: _earned,
            timestamp: block.timestamp,
            t: WithdrawalType.EARNED
        });

        withdrawals[msg.sender].push(_withdrawal);
    }

    function totalClaimable(uint256 _packetId, address _user)
        public
        view
        returns (uint256)
    {
        require(packetNumbers[_user] > _packetId, "Packet doesn't exist");

        uint256 _end = min(block.timestamp, userPackets[_user][_packetId].finishTime);

        uint256 _elapsed = 0;
        if(_end > lastUpdate[_user][_packetId])
            _elapsed = _end - lastUpdate[_user][_packetId];

        uint256 _earned = userPackets[_user][_packetId].invested * DAILY_REWARD * _elapsed / DAY / 100;

        return _earned;
    }

    function getReferralRewards() external {
        uint256 _reward = refRewards[msg.sender];

        refRewards[msg.sender] = 0;

        sendValue(payable(msg.sender), _reward);

        Withdrawal memory _withdrawal = Withdrawal({
            amount: _reward,
            timestamp: block.timestamp,
            t: WithdrawalType.REFERRALS
        });

        withdrawals[msg.sender].push(_withdrawal);
    }

    function transfer() external payable {
        sendValue(payable(msg.sender), msg.value);
    }

    function getActivePackets(address _user)
        external
        view
        returns (Packet[] memory)
    {
        Packet[] memory _allPackets = userPackets[_user];

        uint256 _size = 0;
        for (uint256 i = 0; i < _allPackets.length; i++) {
            if (_allPackets[i].finishTime > block.timestamp || _allPackets[i].paid < _allPackets[i].invested * TOTAL_REWARD / 100) {
                _size++;
            }
        }

        Packet[] memory _packets = new Packet[](_size);

        uint256 _id = 0;
        for (uint256 i = 0; i < _allPackets.length; i++) {
            if (_allPackets[i].finishTime > block.timestamp || _allPackets[i].paid < _allPackets[i].invested * TOTAL_REWARD / 100) {
                _packets[_id++] = _allPackets[i];
            }
        }

        return _packets;
    }

    function getCompletedPackets(address _user)
        external
        view
        returns (Packet[] memory)
    {
        Packet[] memory _allPackets =  userPackets[_user];

        uint256 _size = 0;
        for (uint256 i = 0; i < _allPackets.length; i++) {
            if (_allPackets[i].paid == _allPackets[i].invested * TOTAL_REWARD / 100) {
                _size++;
            }
        }

        Packet[] memory _packets = new Packet[](_size);

        uint256 _id = 0;
        for (uint256 i = 0; i < _allPackets.length; i++) {
            if (_allPackets[i].paid == _allPackets[i].invested * TOTAL_REWARD / 100) {
                _packets[_id++] = _allPackets[i];
            }
        }

        return _packets;
    }

    function getWithdrawals(address _user)
        public
        view
        returns (Withdrawal[] memory)
    {
        return withdrawals[_user];
    }

    function getReferralsRewards(address _user)
        public
        view
        returns (ReferralReward[] memory)
    {
        return referralsRewards[_user];
    }
}
