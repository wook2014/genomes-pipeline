import functools
import logging

try:
    from decorator import decorator
except ImportError:

    def decorator(caller):
        """Turns caller into a decorator.
        Unlike decorator module, function signature is not preserved.

        :param caller: caller(f, *args, **kwargs)
        """

        def decor(f):
            @functools.wraps(f)
            def wrapper(*args, **kwargs):
                return caller(f, *args, **kwargs)

            return wrapper

        return decor


try:  # Python 2.7+
    from logging import NullHandler
except ImportError:

    class NullHandler(logging.Handler):
        def emit(self, record):
            pass
