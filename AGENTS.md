{\rtf1\ansi\ansicpg1252\cocoartf2868
\cocoatextscaling0\cocoaplatform0{\fonttbl\f0\fswiss\fcharset0 Helvetica;}
{\colortbl;\red255\green255\blue255;}
{\*\expandedcolortbl;;}
\paperw11900\paperh16840\margl1440\margr1440\vieww11520\viewh8400\viewkind0
\pard\tx720\tx1440\tx2160\tx2880\tx3600\tx4320\tx5040\tx5760\tx6480\tx7200\tx7920\tx8640\pardirnatural\partightenfactor0

\f0\fs24 \cf0 # AGENTS.md\
\
## Project\
\
- This is an iOS app built with Swift and SwiftUI.\
- Prefer Swift concurrency with async/await.\
- Avoid force unwraps unless there is a clear invariant.\
- Keep UIKit interop isolated unless the existing code already uses it.\
- Follow the existing MVVM/service structure.\
\
## Verification\
\
- For Swift Package changes, run `swift test`.\
- For Xcode project changes, prefer:\
  `xcodebuild test -scheme AppName -destination 'platform=iOS Simulator,name=iPhone 16'`\
- If simulator/device availability prevents tests, explain what was not run.\
\
## Review Focus\
\
- Swift concurrency correctness\
- MainActor usage\
- Retain cycles in closures\
- State ownership in SwiftUI\
- Public API changes}