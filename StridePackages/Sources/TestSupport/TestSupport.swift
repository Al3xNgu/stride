import DomainKit

/// Namespace marker for the `TestSupport` module.
///
/// In-memory fakes of every `DomainKit/Ports` protocol live under
/// `Fakes/` (see `docs/ARCHITECTURE.md` §4 and `CLAUDE.md` rule 5), added
/// alongside each new port. Builders/fixtures for entities will be added
/// here as later tasks need them.
public enum TestSupport {}
