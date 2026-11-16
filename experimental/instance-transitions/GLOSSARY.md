# Deployment Transition Experiment

The language for this independent draft's declarations and deployment state.

## Language

**Interface**:
A versioned concept whose values can be requested by dependent modules without knowing an implementation.

**Module**:
An implementation of one interface that declares its values, configuration and required interfaces. A module does not itself represent a deployment change.

**Instance**:
A module selected, configured and bound to other instances in one desired deployment.

**Transition**:
An explicit deployment operation that changes one instance from a start module to an end module. Either endpoint can be absent, but not both.

**Transition request**:
An explicit choice of which transition to run for an instance. It is an intention, not evidence that its start condition holds on the target.

**Start module**:
The implementation a transition expects to replace or remove, if any. A missing start module does not prove the target is empty.

**End module**:
The implementation the transition intends to bring into use, if any. A missing end module denotes removal.
