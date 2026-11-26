# Ollama Chat for Mac

A small native macOS chat client for local LLMs running on [Ollama](https://ollama.com). No Electron, no account, nothing leaves your machine.

## Features
- Native SwiftUI interface with conversation history
- Pick any installed Ollama model, set a default
- Toggle "thinking" mode for reasoning models (e.g. Qwen3)
- Connect to a local or remote Ollama server

## Build
```bash
./kur.sh   # builds a release binary and installs "Ollama Sohbet.app" into ~/Applications
```
Requires Xcode command line tools and Ollama running locally.

> UI strings and identifiers are in Turkish.
