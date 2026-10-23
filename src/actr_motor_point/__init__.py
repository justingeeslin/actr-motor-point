"""Load and configure spatial reaching in an existing ACT-R server.

Importing this package does not connect to ACT-R. Pass your existing ``actr``
module/client, or omit it to lazily import ACT-R's official Python interface.
"""

from importlib import import_module, resources
from pathlib import Path
from typing import Optional, Sequence

__version__ = "1.0.0"
__all__ = ["load", "configure_limb", "position", "lisp_source"]


def _client(actr):
    if actr is not None:
        return actr
    try:
        return import_module("actr")
    except ModuleNotFoundError as exc:
        if exc.name != "actr":
            raise
        raise ImportError(
            "Make ACT-R's official tutorial/python/actr.py available on your "
            "Python path, or pass your existing ACT-R client as actr=."
        ) from exc


def lisp_source() -> str:
    """Return the bundled Lisp source (e.g. to copy to a remote ACT-R server)."""
    return resources.files(__package__).joinpath("motor-reach.lisp").read_text(
        encoding="utf-8"
    )


def load(actr=None, *, server_path: Optional[str] = None) -> None:
    """Load the extension once per ACT-R server, before defining any models.

    By default ACT-R must share this Python process's filesystem. For another
    host/container, copy ``lisp_source()`` there and pass its absolute pathname
    as ``server_path``. This function does not transfer files or start ACT-R.
    """
    client = _client(actr)
    if server_path is not None:
        result = client.load_act_r_code(str(server_path))
    else:
        resource = resources.files(__package__).joinpath("motor-reach.lisp")
        with resources.as_file(resource) as path:
            result = client.load_act_r_code(str(Path(path).resolve()))
    if not result:
        raise RuntimeError(
            "ACT-R could not load the reaching extension. Check its warning "
            "trace and ensure the Lisp file is accessible on the ACT-R server."
        )


def configure_limb(
    limb: str,
    *,
    position: Optional[Sequence[float]] = None,
    a: Optional[float] = None,
    b: Optional[float] = None,
    actr=None,
) -> None:
    """Configure the current model's limb while manual is free, after reset.

    Omitted values are unchanged. ACT-R validates the limb, coordinates and
    coefficients. Select the model using your client's model context first.
    """
    result = _client(actr).call_command(
        "configure-reach-limb", limb,
        list(position) if position is not None else None, a, b,
    )
    if not result:
        raise RuntimeError("ACT-R rejected limb configuration; check its warning trace.")


def position(limb: str, *, actr=None) -> list:
    """Return the current model's last completed limb position as [x, y, z]."""
    result = _client(actr).call_command("reach-position", limb)
    if result is None or result is False:
        raise RuntimeError("ACT-R could not read limb position; check its warning trace.")
    return list(result)
