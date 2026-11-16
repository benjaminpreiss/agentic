# Deployment Transition Experiment

The language for this independent draft's declarations and deployment operations.

## Language

**Artifact identity**:
A `(kind, authority, name, version)` coordinate identifying a declared interface, module or transition. An instance has a separate deployment-scoped identity.

**Authority**:
The stable DID claimed to control an artifact name and its versions. It is not verified by this draft; a future publisher may act on the authority's behalf.

**Artifact reference**:
A compact string naming an artifact coordinate. It is either scoped to the enclosing declaration's authority or written as a DID URL with a project-defined artifact fragment; neither form proves that the artifact was published by that authority.

**Interface**:
A versioned concept whose values can be requested by dependent modules without knowing an implementation.

**Module**:
An implementation of one interface that declares its values, configuration and required interfaces. A module does not itself represent a deployment change.

**Instance**:
A module selected, configured and bound to other instances in one desired deployment.

**Transition**:
An explicit deployment operation that changes one instance from a `from` module to a `to` module. Either endpoint can be absent, but not both.

**Transition request**:
An explicit choice of which transition to run for an instance. It is an intention, not evidence that its `from` condition holds on the target.

**From module**:
The implementation a transition expects to replace or remove, if any. A missing `from` module does not prove the target is empty.

**To module**:
The implementation the transition intends to bring into use, if any. A missing `to` module denotes removal.
