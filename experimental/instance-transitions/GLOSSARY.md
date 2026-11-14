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

**Applied state**:
The recorded module and bindings previously applied for each instance; it is a planning claim, not an observation proving the target is healthy.
_Avoid_: Discovered state
