//
//  ContentView.swift
//  Stride
//
//  Created by Alex Nguyen on 7/6/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Hello, world!")

                #if DEBUG
                NavigationLink("WorkoutKit Spike (Debug)") {
                    WorkoutKitSpikeView()
                }
                .padding(.top)
                #endif
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
