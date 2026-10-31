"""Run the HermiT reasoner on an ontology (replacement for Protégé's Reasoner menu).

Usage:  python reason.py ontology.owl

Export your ontology from WebProtégé as RDF/XML or OWL/XML (owlready2 can't read Turtle),
save it in this folder, then run the command above.
"""
import sys
from pathlib import Path

from owlready2 import (
    Nothing,
    OwlReadyInconsistentOntologyError,
    default_world,
    get_ontology,
    sync_reasoner,
)


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("Usage: python reason.py <ontology file (.owl / .rdf / .xml)>")

    path = Path(sys.argv[1]).resolve()
    if not path.exists():
        sys.exit(f"File not found: {path}")

    onto = get_ontology(path.as_uri()).load()
    print(f"Loaded {path.name}: {len(list(onto.classes()))} classes, "
          f"{len(list(onto.object_properties()))} object properties, "
          f"{len(list(onto.individuals()))} individuals")

    before = {c: set(c.is_a) for c in onto.classes()}

    try:
        with onto:
            sync_reasoner(infer_property_values=True)  # HermiT
    except OwlReadyInconsistentOntologyError:
        print("\n❌ INCONSISTENT: the ontology contradicts itself. "
              "Undo your last change and run again.")
        return

    unsat = [c for c in default_world.inconsistent_classes() if c is not Nothing]
    if unsat:
        print("\n⚠️  Unsatisfiable classes (can never have members):")
        for c in unsat:
            print(f"   - {c.name}")
    else:
        print("\n✅ Consistent, no unsatisfiable classes.")

    print("\nNew inferences:")
    found = False
    for c in onto.classes():
        new = set(c.is_a) - before.get(c, set())
        for parent in new:
            print(f"   {c.name}  ⊑  {getattr(parent, 'name', parent)}")
            found = True
    for ind in onto.individuals():
        types = ", ".join(t.name for t in ind.is_a if hasattr(t, "name"))
        print(f"   {ind.name} : {types}")
        found = True
    if not found:
        print("   (none)")


if __name__ == "__main__":
    main()
