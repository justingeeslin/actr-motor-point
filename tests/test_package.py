"""Run against an installed wheel: python -m unittest discover -s tests -p 'test_*.py'."""

import sys
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import actr_motor_point as reaching


class PackageTests(unittest.TestCase):
    def test_bundled_source_and_local_load(self):
        client = Mock()

        def load_code(path):
            self.assertTrue(Path(path).is_absolute())
            self.assertEqual(Path(path).read_text(), reaching.lisp_source())
            self.assertIn('(provide "ACTR-MOTOR-REACH")', Path(path).read_text())
            return True

        client.load_act_r_code.side_effect = load_code
        reaching.load(actr=client)
        client.load_act_r_code.assert_called_once()

    def test_remote_path_is_not_resolved_locally(self):
        client = Mock()
        reaching.load(actr=client, server_path="/server/extensions/motor-reach.lisp")
        client.load_act_r_code.assert_called_once_with("/server/extensions/motor-reach.lisp")

    def test_load_failure_surfaces(self):
        for result in (False, None):
            with self.subTest(result=result):
                with self.assertRaises(RuntimeError):
                    reaching.load(actr=Mock(load_act_r_code=Mock(return_value=result)))

    def test_configuration_preserves_zero_and_omits_unspecified(self):
        client = Mock()
        reaching.configure_limb("left-foot", position=(1, 2, 3), a=0, actr=client)
        client.call_command.assert_called_once_with(
            "configure-reach-limb", "left-foot", [1, 2, 3], 0, None
        )

    def test_position(self):
        client = Mock(call_command=Mock(return_value=[1.0, 2.0, 3.0]))
        self.assertEqual(reaching.position("right-hand", actr=client), [1, 2, 3])
        client.call_command.assert_called_once_with("reach-position", "right-hand")

    def test_server_errors_surface(self):
        client = Mock(call_command=Mock(return_value=None))
        with self.assertRaises(RuntimeError):
            reaching.configure_limb("tail", actr=client)
        with self.assertRaises(RuntimeError):
            reaching.position("tail", actr=client)

    def test_default_interface_is_lazy(self):
        client = Mock()
        with patch.dict(sys.modules, {"actr": client}):
            reaching.load()
        client.load_act_r_code.assert_called_once()

    def test_missing_interface_has_setup_message(self):
        with patch("actr_motor_point.import_module", side_effect=ModuleNotFoundError(name="actr")):
            with self.assertRaisesRegex(ImportError, "official"):
                reaching.load()


if __name__ == "__main__":
    unittest.main()
