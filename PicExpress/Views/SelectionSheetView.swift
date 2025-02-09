//
//  SelectionSheetView.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 09/02/2025.
//

import SwiftUI

/// This protocol is used as a common abstraction for selectable items.
/// Our enums (PolygonClippingAlgorithm, FillAlgorithm, ShapeType, etc.) conform to it.
public protocol SelectionItem: Hashable, CustomStringConvertible {}

/// A type-erasing struct that wraps any SelectionItem.
/// This allows us to store different concrete types (enums, structs)
/// in a single array [AnySelectionItem], but still handle them
/// as `SelectionItem`.
public struct AnySelectionItem: SelectionItem {
    // We store the 'base' item as an existential
    public let base: any SelectionItem

    /// Main initializer: wraps a concrete SelectionItem
    public init(_ base: some SelectionItem) {
        self.base = base
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        base.description
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        base.hash(into: &hasher)
    }

    public static func == (lhs: AnySelectionItem, rhs: AnySelectionItem) -> Bool {
        lhs.base.hashValue == rhs.base.hashValue
    }
}

/// A generic view that displays a list of items conforming to `SelectionItem`.
struct SelectionSheetView<T: SelectionItem>: View {
    let title: String
    let options: [T]
    let isPresented: Binding<Bool>
    let onSelection: (T) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
                .padding(.top, 20)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(options, id: \.self) { option in
                        Button(action: {
                            onSelection(option)
                            isPresented.wrappedValue = false
                        }) {
                            Text(option.description)
                                .frame(maxWidth: .infinity)
                                .padding(8)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 50)
            }

            HStack {
                Spacer()
                Button("Annuler") {
                    isPresented.wrappedValue = false
                }
                .padding(.trailing)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
