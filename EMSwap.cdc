import NonFungibleToken from "./External/NonFungibleToken.cdc"
import NFTCatalog from "./External/NFTCatalog.cdc"

access(all) contract EMSwap {

    // ProposalCreated
    // Event to notify when a user has created a swap proposal
    access(all) event ProposalCreated(proposal: ReadableSwapProposal)

    // ProposalExecuted
    // Event to notify when a user has executed a previously created swap proposal
    access(all) event ProposalExecuted(proposal: ReadableSwapProposal)

    // AllowSwapProposalCreation
    // Toggle to control creation of new swap proposals
    access(account) var AllowSwapProposalCreation: Bool

    // SwapCollectionStoragePath
    // Storage directory used to store the SwapCollection object
    access(all) let SwapCollectionStoragePath: StoragePath

    // SwapCollectionPrivatePath
    // Private directory used to expose the SwapCollectionManager object
    access(all) let SwapCollectionPrivatePath: PrivatePath

    // SwapCollectionPublicPath
    // Public directory used to store the SwapCollectionPublic object
    access(all) let SwapCollectionPublicPath: PublicPath

    // SwapProposalAdminStoragePath
    // Storage directory used to store SwapProposalAdmin object
    access(account) let SwapProposalAdminStoragePath: StoragePath

    // SwapProposalAdminPrivatePath
    // Storage directory used to store SwapProposalAdmin object
    access(account) let SwapProposalAdminPrivatePath: PrivatePath

    // SwapProposalMinExpirationMinutes
    // Minimum number of minutes that a swap proposal can be set to expire in
    access(all) let SwapProposalMinExpirationMinutes: UFix64

    // SwapProposalMaxExpirationMinutes
    // Maximum number of minutes that a swap proposal can be set to expire in
    access(all) let SwapProposalMaxExpirationMinutes: UFix64

    // SwapProposalDefaultExpirationMinutes
    // Default nubmer of minutes for swap proposal exiration
    access(all) let SwapProposalDefaultExpirationMinutes: UFix64

    // NftTradeAsset
    // The field to identify a valid NFT within a trade
    // The nftID allows for verification of a valid NFT being transferred
    access(all) struct interface NftTradeAsset {
        access(all) let nftID: UInt64
    }

    access(all) struct interface Readable {
        access(all) fun getReadable(): {String: AnyStruct}
    }

    // ProposedTradeAsset
    // An NFT asset proposed as part of a swap.
    // The init function searches for a corresponding NFTCatalog entry and stores the metadata on the ProposedTradeAsset.
    access(all) struct ProposedTradeAsset: NftTradeAsset, Readable {
        access(all) let nftID: UInt64
        access(all) let type: Type
        access(all) let metadata: NFTCatalog.NFTCatalogMetadata

        access(all) fun getReadable(): {String: String} {
            return {
                "nftID": self.nftID.toString(),
                "type": self.type.identifier
            }
        }

        init(
            nftID: UInt64,
            type: String
        ) {

            let multipleCatalogEntriesMessage: String = "found multiple NFTCatalog entries for "
            let zeroCatalogEntriesMessage: String = "could not find NFTCatalog entry for "
            let nftCatalogTypeMismatch: String = "input type does not match NFTCatalog entry type for "

            // attempt to get NFTCatalog entry from type
            let nftCatalogCollections: {String: Bool}? = NFTCatalog.getCollectionsForType(nftTypeIdentifier: type)

            if (nftCatalogCollections!.keys.length > 1) {
                panic(multipleCatalogEntriesMessage.concat(type))
            } else if (nftCatalogCollections!.keys.length < 1) {
                panic(zeroCatalogEntriesMessage.concat(type))
            }

            let inputType = CompositeType(type) ?? panic("unable to cast type; must be a valid NFT type reference")

            let catalogEntry = NFTCatalog.getCatalogEntry(collectionIdentifier: nftCatalogCollections!.keys[0])
                ?? panic(zeroCatalogEntriesMessage.concat(inputType.identifier))

            assert(inputType == catalogEntry.nftType, message: nftCatalogTypeMismatch.concat(inputType.identifier))

            self.nftID = nftID
            self.type = inputType
            self.metadata = catalogEntry
        }
    }

    // UserOffer
    access(all) struct UserOffer: Readable {
        access(all) let userAddress: Address
        access(all) let proposedNfts: [ProposedTradeAsset]

        access(all) fun getReadable(): {String: [{String: String}]} {

            let readableProposedNfts: [{String: String}] = []
            for proposedNft in self.proposedNfts {
                readableProposedNfts.append(proposedNft.getReadable())
            }

            return {
                "proposedNfts": readableProposedNfts
            }
        }

        init(
            userAddress: Address,
            proposedNfts: [ProposedTradeAsset],
        ) {
            self.userAddress = userAddress
            self.proposedNfts = proposedNfts
        }
    }

    // UserCapabilities
    // This struct contains the providers needed to send the user's offered tokens as well as the receivers needed to
    // accept the trading partner's tokens.
    access(all) struct UserCapabilities {
        access(all) var collectionReceiverCapabilities: {String: Capability<&{NonFungibleToken.Receiver}>}
        access(all) var collectionProviderCapabilities: {String: Capability<&{NonFungibleToken.Provider}>}

        init(
            collectionReceiverCapabilities: {String: Capability<&{NonFungibleToken.Receiver}>},
            collectionProviderCapabilities: {String: Capability<&{NonFungibleToken.Provider}>}
        ) {
            self.collectionReceiverCapabilities = collectionReceiverCapabilities
            self.collectionProviderCapabilities = collectionProviderCapabilities
        }
    }

    // ReadableSwapProposal
    // Struct for return type to SwapProposal.getReadable()
    access(all) struct ReadableSwapProposal {
        access(all) let id: String
        access(all) let minutesRemainingBeforeExpiration: String
        access(all) let leftUserAddress: String
        access(all) let leftUserOffer: {String: [{String: String}]}
        access(all) let rightUserAddress: String
        access(all) let rightUserOffer: {String: [{String: String}]}

        init(
            id: String,
            expirationEpochMilliseconds: UFix64,
            leftUserOffer: UserOffer,
            rightUserOffer: UserOffer
        ) {
            self.id = id
            self.minutesRemainingBeforeExpiration = ((getCurrentBlock().timestamp - expirationEpochMilliseconds) / 60000.0).toString()
            self.leftUserAddress = leftUserOffer.userAddress.toString()
            self.leftUserOffer = leftUserOffer.getReadable()
            self.rightUserAddress = rightUserOffer.userAddress.toString()
            self.rightUserOffer = rightUserOffer.getReadable()
        }
    }

    // SwapProposal
    access(all) struct SwapProposal {

        // Semi-unique identifier (unique within the left user's account) to identify swap proposals
        access(all) let id: String

        // When this swap proposal should no longer be eligible to be accepted (in epoch milliseconds)
        access(all) let expirationEpochMilliseconds: UFix64

        // The offer of the initializing user
        access(all) let leftUserOffer: UserOffer

        // The offer of the secondary proposer
        access(all) let rightUserOffer: UserOffer

        // The trading capabilities of the initializing user
        access(self) let leftUserCapabilities: UserCapabilities

        init(
            id: String,
            leftUserOffer: UserOffer,
            rightUserOffer: UserOffer,
            leftUserCapabilities: UserCapabilities,
            expirationOffsetMinutes: UFix64
        ) {

            assert(expirationOffsetMinutes >= EMSwap.SwapProposalMinExpirationMinutes,
                message: "expirationOffsetMinutes must be greater than or equal to EMSwap.SwapProposalMinExpirationMinutes")
            assert(expirationOffsetMinutes <= EMSwap.SwapProposalMaxExpirationMinutes,
                message: "expirationOffsetMinutes must be less than or equal to EMSwap.SwapProposalMaxExpirationMinutes")
            assert(EMSwap.AllowSwapProposalCreation, message: "swap proposal creation is paused")

            // convert offset minutes to epoch milliseconds
            let expirationEpochMilliseconds = getCurrentBlock().timestamp + (expirationOffsetMinutes * 1000.0 * 60.0)

            // verify that both users own their proposed assets and that leftUser has supplied proper capabilities
            EMSwap.verifyUserOffer(
                userOffer: leftUserOffer,
                userCapabilities: leftUserCapabilities,
                partnerOffer: rightUserOffer
            )
            EMSwap.verifyUserOffer(
                userOffer: rightUserOffer,
                userCapabilities: nil,
                partnerOffer: nil
            )

            self.id = id
            self.leftUserOffer = leftUserOffer
            self.rightUserOffer = rightUserOffer
            self.leftUserCapabilities = leftUserCapabilities
            self.expirationEpochMilliseconds = expirationEpochMilliseconds

            emit ProposalCreated(proposal: self.getReadableSwapProposal())
        }

        // Get a human-readable version of the swap proposal data
        access(contract) fun getReadableSwapProposal(): ReadableSwapProposal {
            return ReadableSwapProposal(
                id: self.id,
                expirationEpochMilliseconds: self.expirationEpochMilliseconds,
                leftUserOffer: self.leftUserOffer,
                rightUserOffer: self.rightUserOffer
            )
        }

        // Function to execute the proposed swap
        access(contract) fun execute(rightUserCapabilities: UserCapabilities) {

            assert(getCurrentBlock().timestamp <= self.expirationEpochMilliseconds, message: "swap proposal is expired")

            // verify capabilities and ownership of tokens
            EMSwap.verifyUserOffer(
                userOffer: self.leftUserOffer,
                userCapabilities: self.leftUserCapabilities,
                partnerOffer: self.rightUserOffer
            )
            EMSwap.verifyUserOffer(
                userOffer: self.rightUserOffer,
                userCapabilities: rightUserCapabilities,
                partnerOffer: self.leftUserOffer
            )

            // execute offers
            EMSwap.executeUserOffer(
                userOffer: self.leftUserOffer,
                userCapabilities: self.leftUserCapabilities,
                partnerCapabilities: rightUserCapabilities
            )
            EMSwap.executeUserOffer(
                userOffer: self.rightUserOffer,
                userCapabilities: rightUserCapabilities,
                partnerCapabilities: self.leftUserCapabilities
            )

            emit ProposalExecuted(proposal: self.getReadableSwapProposal())
        }
    }

    // This interface allows private linking of management methods for the SwapCollection owner
    access(all) resource interface SwapCollectionManager {
        access(all) fun createProposal(
            leftUserOffer: UserOffer,
            rightUserOffer: UserOffer,
            leftUserCapabilities: UserCapabilities,
            expirationOffsetMinutes: UFix64?
        ): String
        access(all) fun getAllProposals(): {String: ReadableSwapProposal}
        access(all) fun deleteProposal(id: String)
    }

    // This interface allows public linking of the get and execute methods for trading partners
    access(all) resource interface SwapCollectionPublic {
        access(all) fun getProposal(id: String): ReadableSwapProposal
        access(all) fun executeProposal(id: String, rightUserCapabilities: UserCapabilities)
    }

    access(all) resource SwapCollection: SwapCollectionManager, SwapCollectionPublic {

        // Dict to store by swap id all trade offers created by the end user
        access(self) let swapProposals: {String: SwapProposal}

        // Function to create and store a swap proposal
        access(all) fun createProposal(
            leftUserOffer: UserOffer,
            rightUserOffer: UserOffer,
            leftUserCapabilities: UserCapabilities,
            expirationOffsetMinutes: UFix64?
        ): String {

            // generate semi-random number for the SwapProposal id
            var semiRandomId: String = unsafeRandom().toString()
            while (self.swapProposals[semiRandomId] != nil) {
                semiRandomId = unsafeRandom().toString()
            }

            // create swap proposal and add to swapProposals
            let newSwapProposal = SwapProposal(
                id: semiRandomId,
                leftUserOffer: leftUserOffer,
                rightUserOffer: rightUserOffer,
                leftUserCapabilities: leftUserCapabilities,
                expirationOffsetMinutes: expirationOffsetMinutes ?? EMSwap.SwapProposalDefaultExpirationMinutes
            )
            self.swapProposals.insert(key: semiRandomId, newSwapProposal)

            return semiRandomId
        }

        // Function to get a readable version of a single swap proposal
        access(all) fun getProposal(id: String): ReadableSwapProposal {

            let noSwapProposalMessage: String = "found no swap proposal with id "
            let swapProposal: SwapProposal = self.swapProposals[id] ?? panic(noSwapProposalMessage.concat(id))

            return swapProposal.getReadableSwapProposal()
        }

        // Function to get a readable version of all swap proposals
        access(all) fun getAllProposals(): {String: ReadableSwapProposal} {

            let proposalReadErrorMessage: String = "unable to get readable swap proposal for id "
            let readableSwapProposals: {String: ReadableSwapProposal} = {}

            for swapProposalId in self.swapProposals.keys {
                let swapProposal = self.swapProposals[swapProposalId] ?? panic(proposalReadErrorMessage.concat(swapProposalId))
                readableSwapProposals.insert(key: swapProposalId, swapProposal!.getReadableSwapProposal())
            }

            return readableSwapProposals
        }

        // Function to delete a swap proposal
        access(all) fun deleteProposal(id: String) {
            self.swapProposals.remove(key: id)
        }

        // Function to execute a previously created swap proposal
        access(all) fun executeProposal(id: String, rightUserCapabilities: UserCapabilities) {

            let noSwapProposalMessage: String = "found no swap proposal with id "
            let swapProposal: SwapProposal = self.swapProposals[id] ?? panic(noSwapProposalMessage.concat(id))

            swapProposal.execute(rightUserCapabilities: rightUserCapabilities)
        }

        init() {
            self.swapProposals = {}
        }
    }

    // SwapProposalManager
    // This interface allows private linking of swap proposal management functionality
    access(all) resource interface SwapProposalManager {
        access(all) fun stopProposalCreation()
        access(all) fun startProposalCreation()
        access(all) fun getProposalCreationStatus(): Bool
    }

    // SwapProposalAdmin
    // This object provides admin controls for swap proposals
    access(all) resource SwapProposalAdmin: SwapProposalManager {

        // Pause all new swap proposal creation (for maintenance)
        access(all) fun stopProposalCreation() {
            EMSwap.AllowSwapProposalCreation = false
        }

        // Resume new swap proposal creation
        access(all) fun startProposalCreation() {
            EMSwap.AllowSwapProposalCreation = true
        }

        // Get current value of AllowSwapProposalCreation
        access(all) fun getProposalCreationStatus(): Bool {
            return EMSwap.AllowSwapProposalCreation
        }
    }

    // createEmptySwapCollection
    // This function allows user to create a swap collection resource for future swap proposal creation.
    access(all) fun createEmptySwapCollection(): @SwapCollection {
        return <-create SwapCollection()
    }

    // verifyUserOffer
    // This function verifies that all assets in user offer are owned by the user.
    // If userCapabilities is provided, the function checks that the provider capabilities are valid and that the
    // address of each capability matches the address of the userOffer.
    // If partnerOffer is provided in addition to userCapabilities, the function checks that the receiver
    // capabilities are valid and that one exists for each of the collections in the partnerOffer.
    access(contract) fun verifyUserOffer(userOffer: UserOffer, userCapabilities: UserCapabilities?, partnerOffer: UserOffer?) {

        let nftCatalogMessage: String = "NFTCatalog entry not found for "
        let collectionPublicMessage: String = "could not borrow collectionPublic for "
        let typeMismatchMessage: String = "proposedNft.type and stored asset type do not match for "
        let ownershipMessage: String = "could not verify ownership for "
        let capabilityNilMessage: String = "capability not found for "
        let addressMismatchMessage: String = "capability address does not match userOffer address for "
        let capabilityCheckMessage: String = "capability is invalid for "

        let userPublicAccount: PublicAccount = getAccount(userOffer.userAddress)

        for proposedNft in userOffer.proposedNfts {

            // attempt to load CollectionPublic capability and verify ownership
            let publicCapability = userPublicAccount.getCapability(proposedNft.metadata.collectionData.publicPath)

            let collectionPublicRef = publicCapability.borrow<&AnyResource{NonFungibleToken.CollectionPublic}>()
                ?? panic(collectionPublicMessage.concat(proposedNft.type.identifier))

            let ownedNftIds: [UInt64] = collectionPublicRef.getIDs()
            assert(ownedNftIds.contains(proposedNft.nftID), message: ownershipMessage.concat(proposedNft.type.identifier))

            let nftRef = collectionPublicRef.borrowNFT(id: proposedNft.nftID)
            assert(nftRef.getType() == proposedNft.getType(), message: typeMismatchMessage.concat(proposedNft.type.identifier))

            if (userCapabilities != nil) {

                // check provider capabilities
                let providerCapability = userCapabilities!.collectionProviderCapabilities[proposedNft.type.identifier]
                assert(providerCapability != nil, message: capabilityNilMessage.concat(proposedNft.type.identifier))
                assert(providerCapability!.address == userOffer.userAddress, message: addressMismatchMessage.concat(proposedNft.type.identifier))
                assert(providerCapability!.check(), message: capabilityCheckMessage.concat(proposedNft.type.identifier))
            }
        }

        if (userCapabilities != nil && partnerOffer != nil) {

            // check receiver capabilities
            for partnerProposedNft in partnerOffer!.proposedNfts {

                let receiverCapability = userCapabilities!.collectionReceiverCapabilities[partnerProposedNft.type.identifier]
                assert(receiverCapability != nil, message: capabilityNilMessage.concat(partnerProposedNft.type.identifier))
                assert(receiverCapability!.address == userOffer.userAddress, message: addressMismatchMessage.concat(partnerProposedNft.type.identifier))
                assert(receiverCapability!.check(), message: capabilityCheckMessage.concat(partnerProposedNft.type.identifier))
            }
        }
    }

    // executeUserOffer
    // This function verifies for each token in the user offer that both users have the required capabilites for the
    // trade and that the token type matches that of the offer, and then it moves the token to the receiving collection.
    access(contract) fun executeUserOffer(
        userOffer: UserOffer,
        userCapabilities: UserCapabilities,
        partnerCapabilities: UserCapabilities
    ) {

        let typeMismatchMessage: String = "token type mismatch for "
        let receiverRefMessage: String = "could not borrow receiver reference for "
        let providerRefMessage: String = "could not borrow provider reference for "

        for proposedNft in userOffer.proposedNfts {

            // get receiver and provider
            let receiverReference = partnerCapabilities.collectionReceiverCapabilities[proposedNft.type.identifier]!.borrow()
                ?? panic(receiverRefMessage.concat(proposedNft.type.identifier))
            let providerReference = userCapabilities.collectionProviderCapabilities[proposedNft.type.identifier]!.borrow()
                ?? panic(providerRefMessage.concat(proposedNft.type.identifier))

            // verify token type
            let nft <- providerReference.withdraw(withdrawID: proposedNft.nftID)
            assert(nft.isInstance(proposedNft.type), message: typeMismatchMessage.concat(proposedNft.type.identifier))

            // move token
            receiverReference.deposit(token: <-nft)
        }
    }

    init() {

        // initialize contract constants
        self.AllowSwapProposalCreation = true
        self.SwapCollectionStoragePath = /storage/emSwapCollection
        self.SwapCollectionPrivatePath = /private/emSwapCollectionManager
        self.SwapCollectionPublicPath = /public/emSwapCollectionPublic
        self.SwapProposalAdminStoragePath = /storage/emSwapProposalAdmin
        self.SwapProposalAdminPrivatePath = /private/emSwapProposalAdmin
        self.SwapProposalMinExpirationMinutes = 2.0
        self.SwapProposalMaxExpirationMinutes = 20.0
        self.SwapProposalDefaultExpirationMinutes = 5.0

        // save swap proposal admin object
        self.account.save(<- create SwapProposalAdmin(), to: self.SwapProposalAdminStoragePath)
        self.account.link<&{SwapProposalManager}>(self.SwapProposalAdminPrivatePath, target: self.SwapProposalAdminStoragePath)
    }
}
