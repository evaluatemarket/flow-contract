import EMSwap from 0xf8d6e0586b0a20c7
import MetadataViews from 0xf8d6e0586b0a20c7

// This transaction attempts to execute the specified swap proposal.
// It should be signed by the right user on the swap proposal.
transaction(leftUserAddress: Address, swapProposalId: String) {

    let rightUserReceiverCapabilities: {String: Capability<&{NonFungibleToken.Receiver}>}
    let rightUserProviderCapabilities: {String: Capability<&{NonFungibleToken.Provider}>}
    let swapCollectionPublicCapability: Capability<&AnyResource{EMSwap.SwapCollectionPublic}>

    prepare(acct: AuthAccount) {

        let leftUserAccount: PublicAccount = getAccount(leftUserAddress)

        self.swapCollectionPublicCapability = leftUserAccount.getCapability<&AnyResource{EMSwap.SwapCollectionPublic}>(EMSwap.SwapCollectionPublicPath)
        assert(self.swapCollectionPublicCapability.check(), message: "invalid SwapCollectionPublic capability")

        // get right user receiver capabilities and create missing capabilities and collections for the user if possible
        self.rightUserReceiverCapabilities = {}

        let receiverLinkFailedMessage: String = "unable to create public link to collection receiver for "
        let partnerResolverCollectionMessage: String = "unable to borrow partner resolver collection for "
        let newCollectionMessage: String = "unable to create new collection for "

        let partnerPublicAccount: PublicAccount = getAccount(partnerOffer.userAddress)

        for partnerProposedNft in self.leftUserOffer.proposedNfts {

            // check that receiver capability exists or create if necessary
            if (self.rightUserReceiverCapabilities[partnerProposedNft.type.identifier] == nil) {

                if (acct.type(at: partnerProposedNft.collectionStoragePath!) != nil) {

                    // attempt to get capability from stored public path
                    let receiverCapability = acct.getCapability<&AnyResource{NonFungibleToken.Receiver}>(partnerProposedNft.collectionPublicPath!)
                    if (receiverCapability.check()) {
                        self.rightUserReceiverCapabilities[partnerProposedNft.type.identifier] = receiverCapability
                    } else {

                        // create a new receiver capability
                        let newReceiverCapability = acct.link<&AnyResource{NonFungibleToken.Receiver}>(partnerProposedNft.collectionPublicPath!, target: partnerProposedNft.collectionStoragePath!)
                            ?? panic(receiverLinkFailedMessage.concat(partnerProposedNft.type.identifier))
                        self.rightUserReceiverCapabilities[partnerProposedNft.type.identifier] = newReceiverCapability
                    }

                } else {

                    // attempt to get createEmptyCollection() reference from partner's storage
                    let partnerResolverCollectionRef = partnerPublicAccount.getCapability<&AnyResource{MetadataViews.ResolverCollection}>(partnerProposedNft.collectionPublicPath!).borrow()
                        ?? panic(partnerResolverCollectionMessage.concat(partnerProposedNft.type.identifier))

                    let viewResolver = partnerResolverCollectionRef!.borrowViewResolver(id: partnerProposedNft.nftID)
                    let collectionData = MetadataViews.getNFTCollectionData(viewResolver)
                        ?? panic("could not get NFTCollectionData from partnerResolverCollectionRef")

                    let emptyCollection: @NonFungibleToken.Collection <- collectionData.createEmptyCollection()

                    if (emptyCollection != nil) {

                        // create new collection and save
                        acct.save<@NonFungibleToken.Collection>(<-emptyCollection!, to: partnerProposedNft.collectionStoragePath!)
                        let receiverCapability = acct.link<&{NonFungibleToken.Receiver}>(partnerProposedNft.collectionPublicPath!, target: partnerProposedNft.collectionStoragePath!)
                            ?? panic(receiverLinkFailedMessage.concat(partnerProposedNft.type.identifier))
                        self.rightUserReceiverCapabilities[partnerProposedNft.type.identifier] = receiverCapability

                    } else {
                        panic(newCollectionMessage.concat(partnerProposedNft.type.identifier))
                    }
                }
            }
        }

        // get right user provider capabilities and create missing capabilities if possible
        self.rightUserProviderCapabilities = {}

        let providerLinkFailedMessage: String = "unable to create private link to collection provider for "

        for proposedNft in self.rightUserOffer.proposedNfts {

            // check that provider capability exists or create if necessary
            if (self.rightUserProviderCapabilities[proposedNft.type.identifier] == nil) {

                // attempt to get capability from stored private path
                let providerCapability = acct.getCapability<&AnyResource{NonFungibleToken.Provider}>(proposedNft.collectionPrivatePath!)
                if (providerCapability.check()) {
                    self.rightUserProviderCapabilities[proposedNft.type.identifier] = providerCapability
                } else {

                    // create a new provider capability
                    let newProviderCapability = acct.link<&AnyResource{NonFungibleToken.Provider}>(proposedNft.collectionPrivatePath!, target: proposedNft.collectionStoragePath!)
                        ?? panic(providerLinkFailedMessage.concat(proposedNft.type.identifier))
                    self.rightUserProviderCapabilities[proposedNft.type.identifier] = newProviderCapability
                }
            }
        }
    }

    execute {

        let swapCollectionPublic = swapCollectionPublicCapability.borrow()!
        let readableSwapProposal = swapCollectionPublic.getProposal(id: swapProposalId)
        log(readableSwapProposal) // add user check of proposal terms here

        self.swapCollectionPublic.executeProposal(
            id: swapProposalId,
            rightUserCapabilities: EMSwap.UserCapabilities(
                collectionReceiverCapabilities: self.rightUserReceiverCapabilities,
                collectionProviderCapabilities: self.rightUserProviderCapabilities
            )
        )
    }
}
