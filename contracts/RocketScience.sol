// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6;

import "./Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

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
    uint256 t; // 1 - earned withdrawals, 2 - referrals withdrawals
}

struct ReferralReward {
    address user;
    uint256 amount;
    uint256 timestamp;
}

contract RocketScience is Ownable {
    using SafeMath for uint256;

    uint256 public constant PACKET_LIFETIME = 15 days;
    uint256 public constant DAY = 1 days;
    uint256 public constant REF = 10;

    uint256 public constant DAILY_REWARD = 15; // %

    uint256 public totalInvest;
    uint256 public totalInvestors;

    mapping(address => Investor) investors;
    mapping(address => mapping(uint256 => uint256)) lastUpdate;

    mapping(address => uint256) refRewards;

    mapping(address => Withdrawal[]) withdrawals;
    mapping(address => ReferralReward[]) referralsRewards;

    mapping(address => mapping(address => bool)) referrals;

    mapping(address => Packet[]) userPackets;
    mapping(address => uint256) packetNumbers;

    //receive() external payable{}
    fallback() external payable{
        payable(msg.sender).transfer(msg.value);
    }

    constructor() {
        Investor memory _investorOwner;
        _investorOwner.referrer = address(this);

        investors[owner()] = _investorOwner;
        totalInvestors++;
    }

    function invest() public payable {
        require(
            msg.value >= 10000000000000000 &&
                msg.value <= 1000000000000000000000,
            "Wrong amount"
        );

        uint256 _packetId = packetNumbers[msg.sender];

        uint256 _earn = msg.value.mul(REF).div(100);

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
        payable(owner()).transfer(msg.value.div(10));
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

    function investByRef(address _referrer) public payable {
        require(msg.sender != _referrer, "You can't invest to youself");
        require(
            msg.value >= 10000000000000000 &&
                msg.value <= 1000000000000000000000,
            "Wrong amount"
        );

        bool _isNew;
        if (investors[msg.sender].referrer == address(0)) _isNew = true;
        else _referrer = investors[msg.sender].referrer;

        if (_isNew) {
            investors[msg.sender].referrer = _referrer;
            totalInvestors++;
        }

        uint256 _packetId = packetNumbers[msg.sender];
        uint256 _earn = msg.value.mul(REF).div(100);
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
        payable(owner()).transfer(msg.value.div(10));
    }

    function takeInvestment(uint256 _packetId) public {
        require(packetNumbers[msg.sender] > _packetId, "Packet doesn't exist");

        uint256 _earned;
        if (
            block.timestamp > userPackets[msg.sender][_packetId].finishTime &&
            lastUpdate[msg.sender][_packetId] >
            userPackets[msg.sender][_packetId].finishTime
        ) {
            _earned = 0;
        } else if (
            block.timestamp > userPackets[msg.sender][_packetId].finishTime &&
            lastUpdate[msg.sender][_packetId] <
            userPackets[msg.sender][_packetId].finishTime
        ) {
            _earned = userPackets[msg.sender][_packetId].invested.mul(225).div(100).sub(
                userPackets[msg.sender][_packetId].paid
            );
        } else {
            _earned = userPackets[msg.sender][_packetId]
                .invested
                .mul(DAILY_REWARD)
                .mul(block.timestamp - lastUpdate[msg.sender][_packetId])
                .div(DAY)
                .div(100);
        }

        lastUpdate[msg.sender][_packetId] = block.timestamp;
        investors[msg.sender].earned += _earned;

        userPackets[msg.sender][_packetId].paid += _earned;

        payable(msg.sender).transfer(_earned);

        Withdrawal memory _withdrawal = Withdrawal({
            amount: _earned,
            timestamp: block.timestamp,
            t: 1
        });

        withdrawals[msg.sender].push(_withdrawal);
    }

    function totalClaimable(uint256 _packetId, address _user)
        public
        view
        returns (uint256)
    {
        require(packetNumbers[_user] > _packetId, "Packet doesn't exist");

        uint256 _earned;
        if (
            block.timestamp > userPackets[_user][_packetId].finishTime &&
            lastUpdate[_user][_packetId] >
            userPackets[_user][_packetId].finishTime
        ) {
            _earned = 0;
        } else if (
            block.timestamp > userPackets[_user][_packetId].finishTime &&
            lastUpdate[_user][_packetId] <
            userPackets[_user][_packetId].finishTime
        ) {
            _earned = userPackets[_user][_packetId].invested.mul(225).div(100).sub(
                userPackets[_user][_packetId].paid
            );
        } else {
            _earned = userPackets[_user][_packetId]
                .invested
                .mul(DAILY_REWARD)
                .mul(block.timestamp - lastUpdate[_user][_packetId])
                .div(DAY)
                .div(100);
        }

        return _earned;
    }

    function getReferralRewards() public {
        uint256 _reward = refRewards[msg.sender];

        refRewards[msg.sender] = 0;

        payable(msg.sender).transfer(_reward);

        Withdrawal memory _withdrawal = Withdrawal({
            amount: _reward,
            timestamp: block.timestamp,
            t: 2
        });

        withdrawals[msg.sender].push(_withdrawal);
    }

    function transfer() external payable {
        payable(msg.sender).transfer(msg.value);
    }

    function getInvestor(address _investor)
        public
        view
        returns (Investor memory)
    {
        return investors[_investor];
    }

    // function getAllPackets(address _user)
    //     public
    //     view
    //     returns (Packet[] memory)
    // {
    //     return userPackets[_user];
    // }

    function getActivePackets(address _user)
        public
        view
        returns (Packet[] memory)
    {
        Packet[] memory _allPackets = userPackets[_user];

        uint256 _size = 0;
        for (uint256 i = 0; i < _allPackets.length; i++) {
            if (_allPackets[i].finishTime > block.timestamp || _allPackets[i].paid < _allPackets[i].invested.mul(224).div(100)) {
                _size++;
            }
        }

        Packet[] memory _packets = new Packet[](_size);

        uint256 _id = 0;
        for (uint256 i = 0; i < _allPackets.length; i++) {
            if (_allPackets[i].finishTime > block.timestamp || _allPackets[i].paid < _allPackets[i].invested.mul(224).div(100)) {
                _packets[_id++] = _allPackets[i];
            }
        }

        return _packets;
    }

    function getCompletedPackets(address _user)
        public
        view
        returns (Packet[] memory)
    {
        Packet[] memory _allPackets =  userPackets[_user];

        uint256 _size = 0;
        for (uint256 i = 0; i < _allPackets.length; i++) {
            if (_allPackets[i].finishTime < block.timestamp && _allPackets[i].paid > _allPackets[i].invested.mul(224).div(100)) {
                _size++;
            }
        }

        Packet[] memory _packets = new Packet[](_size);

        uint256 _id = 0;
        for (uint256 i = 0; i < _allPackets.length; i++) {
            if (_allPackets[i].finishTime < block.timestamp && _allPackets[i].paid > _allPackets[i].invested.mul(224).div(100)) {
                _packets[_id++] = _allPackets[i];
            }
        }

        return _packets;
    }

    function getCurrentRefRewards(address _user) public view returns (uint256) {
        return refRewards[_user];
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