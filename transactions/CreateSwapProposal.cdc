import EMSwap from 0xf8d6e0586b0a20c7
import DriverzNFT from 0xf8d6e0586b0a20c7
import MetadataViews from 0xf8d6e0586b0a20c7

// This transaction creates a new swap proposal.
// It should be signed by the initializing user aka the left user.
transaction() {

    let leftUserOffer: EMSwap.UserOffer
    let rightUserOffer: EMSwap.UserOffer
    let leftUserReceiverCapabilities: {String: Capability<&{NonFungibleToken.Receiver}>}
    let leftUserProviderCapabilities: {String: Capability<&{NonFungibleToken.Provider}>}
    let leftUserAccount: AuthAccount

    prepare(acct: AuthAccount) {

        let driverzResolverCollectionCapability = acct.getCapability<&AnyResource{MetadataViews.ResolverCollection}>(/public/DriverzNFTCollection)

        let leftProposedNfts: [EMSwap.ProposedTradeAsset] = [
            EMSwap.ProposedTradeAsset(
                nftID: 555,
                type: "A.0xa039bd7d55a96c0c.DriverzNFT.NFT"
            )
        ]

        let rightProposedNfts: [EMSwap.ProposedTradeAsset] = [
            EMSwap.ProposedTradeAsset(
                nftID: 789,
                type: "A.921ea449dffec68a.Flovatar.NFT"
            )
        ]

        self.leftUserOffer = EMSwap.UserOffer(userAddress: acct.address, proposedNfts: leftProposedNfts)
        self.rightUserOffer = EMSwap.UserOffer(userAddress: 0xf8d6e0586b0a20c8, proposedNfts: rightProposedNfts)

        // get left user receiver capabilities and create missing capabilities and collections for the user if possible
        self.leftUserReceiverCapabilities = {}

        let receiverLinkFailedMessage: String = "unable to create public link to collection receiver for "
        let providerLinkFailedMessage: String = "unable to create private link to collection provider for "
        let partnerResolverCollectionMessage: String = "unable to borrow partner resolver collection for "
        let newCollectionMessage: String = "unable to create new collection for "

        let partnerPublicAccount: PublicAccount = getAccount(partnerOffer.userAddress)

        for partnerProposedNft in self.rightUserOffer.proposedNfts {

            // check that receiver capability exists or create if necessary
            if (self.leftUserReceiverCapabilities[partnerProposedNft.type.identifier] == nil) {

                if (acct.type(at: partnerProposedNft.metadata.collectionData.storagePath) != nil) {

                    // attempt to get capability from public path
                    let receiverCapability = acct.getCapability<&AnyResource{NonFungibleToken.Receiver}>(partnerProposedNft.metadata.collectionData.publicPath)
                    if (receiverCapability.check()) {
                        self.leftUserReceiverCapabilities[partnerProposedNft.type.identifier] = receiverCapability
                    } else {

                        // create a new receiver capability
                        let newReceiverCapability = acct.link<&AnyResource{NonFungibleToken.Receiver}>(partnerProposedNft.metadata.collectionData.publicPath, target: partnerProposedNft.metadata.collectionData.storagePath)
                            ?? panic(receiverLinkFailedMessage.concat(partnerProposedNft.type.identifier))
                        self.leftUserReceiverCapabilities[partnerProposedNft.type.identifier] = newReceiverCapability
                    }

                } else {

                    // attempt to get createEmptyCollection() reference from partner's storage
                    let partnerResolverCollectionRef = partnerPublicAccount.getCapability<&AnyResource{MetadataViews.ResolverCollection}>(partnerProposedNft.metadata.collectionData.publicPath).borrow()
                        ?? panic(partnerResolverCollectionMessage.concat(partnerProposedNft.type.identifier))

                    let viewResolver = partnerResolverCollectionRef!.borrowViewResolver(id: partnerProposedNft.nftID)
                    let collectionData = MetadataViews.getNFTCollectionData(viewResolver)
                        ?? panic("could not get NFTCollectionData from partnerResolverCollectionRef")

                    let emptyCollection: @NonFungibleToken.Collection <- collectionData.createEmptyCollection()

                    if (emptyCollection != nil) {

                        // create new collection and save
                        acct.save<@NonFungibleToken.Collection>(<-emptyCollection!, to: partnerProposedNft.metadata.collectionData.storagePath)
                        let receiverCapability = acct.link<&{NonFungibleToken.Receiver}>(partnerProposedNft.metadata.collectionData.publicPath, target: partnerProposedNft.metadata.collectionData.storagePath)
                            ?? panic(receiverLinkFailedMessage.concat(partnerProposedNft.type.identifier))
                        self.leftUserReceiverCapabilities[partnerProposedNft.type.identifier] = receiverCapability

                    } else {
                        panic(newCollectionMessage.concat(partnerProposedNft.type.identifier))
                    }
                }
            }
        }

        // get left user provider capabilities and create missing capabilities if possible
        self.leftUserProviderCapabilities = {}

        for proposedNft in self.leftUserOffer.proposedNfts {

            // check that provider capability exists or create if necessary
            if (self.leftUserProviderCapabilities[proposedNft.type.identifier] == nil) {

                // attempt to get capability from stored private path
                let providerCapability = acct.getCapability<&AnyResource{NonFungibleToken.Provider}>(proposedNft.metadata.collectionData.privatePath)
                if (providerCapability.check()) {
                    self.leftUserProviderCapabilities[proposedNft.type.identifier] = providerCapability
                } else {

                    // create a new provider capability
                    let newProviderCapability = acct.link<&AnyResource{NonFungibleToken.Provider}>(proposedNft.metadata.collectionData.privatePath, target: proposedNft.metadata.collectionData.storagePath)
                        ?? panic(providerLinkFailedMessage.concat(proposedNft.type.identifier))
                    self.leftUserProviderCapabilities[proposedNft.type.identifier] = newProviderCapability
                }
            }
        }
    }

    execute {

        if (leftUserAccount.type(at: EMSwap.SwapCollectionStoragePath) == nil) {

            // create new swap collection
            let newSwapCollection <- EMSwap.createEmptySwapCollection()
            leftUserAccount.save(newSwapCollection, to: EMSwap.SwapCollectionStoragePath)

            // link swap collection private and public capabilities
            leftUserAccount.link<&AnyResource{EMSwap.SwapCollectionManager}>(EMSwap.SwapCollectionPrivatePath, target: EMSwap.SwapCollectionStoragePath)
            leftUserAccount.link<&AnyResource{EMSwap.SwapCollectionPublic}>(EMSwap.SwapCollectionPublicPath, target: EMSwap.SwapCollectionStoragePath)

        } else if (leftUserAccount.type(at: EMSwap.SwapCollectionStoragePath) != Type<EMSwap.SwapCollection>()) {
            panic("incorrect collection type stored at EMSwap.SwapCollectionStoragePath")
        }

        // get private swap collection capability
        let swapCollectionManagerCapability = leftUserAccount.getCapability<&AnyResource{EMSwap.SwapCollectionManager}>(EMSwap.SwapCollectionPrivatePath)
        assert(swapCollectionManagerCapability.check(), message: "got invalid SwapCollectionManager capability")
        let swapCollectionManager = swapCollectionManagerCapability.borrow()!

        let proposalId = swapCollectionManager.createProposal(
            leftUserOffer: self.leftUserOffer,
            rightUserOffer: self.rightUserOffer,
            leftUserCapabilities: EMSwap.UserCapabilities(
                collectionReceiverCapabilities: self.leftUserReceiverCapabilities,
                collectionProviderCapabilities: self.leftUserProviderCapabilities
            ),
            expirationOffsetMinutes: EMSwap.SwapProposalDefaultExpirationMinutes
        )

        return proposalId
    }
}
