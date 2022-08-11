// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract Web3RSVP {
    event NewEventCreated(
        bytes32 eventID,
        address creatorAddress,
        uint256 eventTimestamp,
        uint256 maxCapacity,
        uint256 deposit,
        string eventDataCID
    );

    event NewRSVP(bytes32 eventID, address attendeeAddress);

    event ConfirmedAttendee(bytes32 eventID, address attendeeAddress);

    event DepositsPaidOut(bytes32 eventID);

    struct CreateEvent {
        bytes32 eventId;
        string eventDataCID;
        address eventOwner;
        uint256 eventTimestamp;
        uint256 deposit;
        uint256 maxCapacity;
        address[] confirmedRSVPs;
        address[] claimedRSVPs;
        bool paidOut;
    }

    mapping(bytes32 => CreateEvent) public idToEvent;

    function createNewEvent(
        uint256 eventTimestamp,
        uint256 deposit,
        uint256 maxCapacity,
        string calldata eventDataCID
    ) external {
        bytes32 eventId = keccak256(
            abi.encodePacked(
                msg.sender,
                address(this),
                eventTimestamp,
                deposit,
                maxCapacity
            )
        );
        address[] memory confirmedRSVPs;
        address[] memory claimedRSVPs;

        idToEvent[eventId] = CreateEvent(
            eventId,
            eventDataCID,
            msg.sender,
            eventTimestamp,
            deposit,
            maxCapacity,
            confirmedRSVPs,
            claimedRSVPs,
            false
        );
        emit NewEventCreated(
            eventId,
            msg.sender,
            eventTimestamp,
            maxCapacity,
            deposit,
            eventDataCID
        );
    }

    function createNewRSVP(bytes32 eventId) external payable {
        CreateEvent storage myEvent = idToEvent[eventId];
        require(msg.value == myEvent.deposit, "Insufficient funds");
        require(
            block.timestamp <= myEvent.eventTimestamp,
            "Event has already happened!"
        );
        require(
            myEvent.confirmedRSVPs.length < myEvent.maxCapacity,
            "Sorrry, this event has reached full capacity"
        );
        for (uint8 i = 0; i < myEvent.confirmedRSVPs.length; i++) {
            require(
                myEvent.confirmedRSVPs[i] != msg.sender,
                "This person has already RSVPD!"
            );
        }
        myEvent.confirmedRSVPs.push(payable(msg.sender));
        emit NewRSVP(eventId, msg.sender);
    }

    function confirmAttendee(bytes32 eventId, address attendee) public {
        CreateEvent storage myEvent = idToEvent[eventId];
        require(
            msg.sender == myEvent.eventOwner,
            "You are not authorized to check guest attendence"
        );
        // check guest is vaild/ has rsvp to reveice their ETH back
        address rsvpConfirm;

        for (uint8 i = 0; i < myEvent.confirmedRSVPs.length; i++) {
            if (myEvent.confirmedRSVPs[i] == attendee) {
                rsvpConfirm = myEvent.confirmedRSVPs[i];
            }
        }

        require(rsvpConfirm == attendee, "NO RSVP TO CONFIRM");

        // make sure deposit hasn't already been paid out
        for (uint8 i = 0; i < myEvent.claimedRSVPs.length; i++) {
            require(
                myEvent.claimedRSVPs[i] != attendee,
                "You have already caimed your deposit"
            );
        }

        // require that deposits are not already claimed by the event owner
        require(myEvent.paidOut == false, "ALREADY PAID OUT");
        myEvent.claimedRSVPs.push(attendee);

        // sending eth back to the staker `https://solidity-by-example.org/sending-ether`
        (bool sent, ) = attendee.call{value: myEvent.deposit}(
            "Deposit refunded"
        );
        // if this fails, remove the user from the array of claimed RSVPs
        if (!sent) {
            myEvent.claimedRSVPs.pop();
        }
        require(sent, "Failed to send Ether");

        emit ConfirmedAttendee(eventId, attendee);
    }

    // check whole group attendence
    function confirmAllAttendees(bytes32 eventId) external {
        // look up event
        CreateEvent memory myEvent = idToEvent[eventId];
        require(
            msg.sender == myEvent.eventOwner,
            "You are not authorized to check guest attendence"
        );
        // confirm each attendee in the rsvp array
        for (uint8 i = 0; i < myEvent.confirmedRSVPs.length; i++) {
            confirmAttendee(eventId, myEvent.confirmedRSVPs[i]);
        }
    }

    function withdrawUnclaimedDeposits(bytes32 eventId) external {
        CreateEvent memory myEvent = idToEvent[eventId];
        require(!myEvent.paidOut, "Deposit already paid");

        // check if it's been 7 days past myEvent.eventTimestamp
        require(
            block.timestamp >= (myEvent.eventTimestamp + 7 days),
            "TOO EARLY"
        );

        // only the event owner can withdraw
        require(
            msg.sender == myEvent.eventOwner,
            "Only event owner cna withdraw funds"
        );

        // calculate how many people didn't claim by comparing
        uint256 unclaimed = myEvent.confirmedRSVPs.length -
            myEvent.claimedRSVPs.length;
        uint256 payout = unclaimed * myEvent.deposit;
        // mark as paid before sending to avoid reentrancy attack
        myEvent.paidOut = true;
        // send the payout to the owner
        (bool sent, ) = msg.sender.call{value: payout}(
            "Funds sent successfully"
        );

        // if this fails
        if (!sent) {
            myEvent.paidOut == false;
        }
        require(sent, "Failed to send Ether");

        emit DepositsPaidOut(eventId);
    }
}
