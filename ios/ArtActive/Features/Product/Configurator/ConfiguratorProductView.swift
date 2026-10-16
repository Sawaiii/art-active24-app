import SwiftUI

/// Шаблон 128 «Карточка товара 2026»: конфигуратор + липкий бар цены.
/// Режимы: standard, trampoline, cateringMenu, masterclass.
struct ConfiguratorProductView: View {
    @State private var viewModel: ConfiguratorViewModel

    init(viewModel: ConfiguratorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        let product = viewModel.product
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GalleryPager(items: GalleryItem.from(product.media), badge: product.badge)

                VStack(alignment: .leading, spacing: 26) {
                    ProductTitleRow(product: product)
                    configuratorSteps
                    if let comment = viewModel.complect?.comment, !comment.isEmpty {
                        InfoNote(title: comment, systemImage: "info.circle")
                    }
                    if let specs = product.specs, !specs.isEmpty {
                        SpecsSection(specs: specs)
                    }
                    if let html = product.descriptionHtml, !html.isEmpty {
                        DescriptionSection(html: html)
                    }
                    if viewModel.mode == .masterclass, let masterclass = product.masterclass {
                        MasterclassInfoSection(masterclass: masterclass)
                    }
                }
                .padding(.horizontal, Spacing.gutterProduct)
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 32) {
                    if !viewModel.configurator.alsoFitsGroups.isEmpty {
                        AlsoFitsSection(viewModel: viewModel)
                    }
                    if viewModel.mode == .masterclass, let masterclass = product.masterclass {
                        MasterclassRelatedSection(masterclass: masterclass)
                    } else if let similar = product.similar, !similar.isEmpty {
                        SimilarSection(title: String(localized: "Похожие товары"), products: similar)
                    }
                    ManagerContactSection()
                        .padding(.horizontal, Spacing.gutterProduct)
                }
                .padding(.top, 36)
                .padding(.bottom, 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.state != nil {
                StickyCartBar(viewModel: viewModel)
            }
        }
        .toolbar {
            if let url = viewModel.shareURL {
                ToolbarItem(placement: .secondaryAction) {
                    ShareLink(item: url, subject: Text(product.name)) {
                        Label("Поделиться конфигурацией", systemImage: "link")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var configuratorSteps: some View {
        VStack(alignment: .leading, spacing: 24) {
            if viewModel.configurator.showsComplectPicker || viewModel.mode == .masterclass {
                ComplectsStep(viewModel: viewModel)
            }
            if viewModel.priceTypes.count > 1 {
                PriceTypeStep(viewModel: viewModel)
            }
            if viewModel.mode == .masterclass, let masterclass = viewModel.product.masterclass {
                MasterclassVenuesButton(masterclass: masterclass)
            }
            if !viewModel.subGroups.isEmpty {
                SubsStep(viewModel: viewModel)
            }
            if viewModel.mode == .cateringMenu {
                CateringMenuStep(viewModel: viewModel)
            }
            if let options = viewModel.timeOptions {
                TimeStep(viewModel: viewModel, options: options)
            }
            if !viewModel.configurator.plainExtras.isEmpty {
                ExtrasStep(viewModel: viewModel)
            }
        }
    }
}
