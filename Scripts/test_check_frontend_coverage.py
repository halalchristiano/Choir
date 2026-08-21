import unittest

from check_frontend_coverage import is_linguistic_frontend_source


class LinguisticFrontendPathTests(unittest.TestCase):
    def test_accepts_absolute_relative_and_windows_paths(self) -> None:
        paths = [
            "/checkout/Sources/Choir/LinguisticFrontend/TextNormalizer.swift",
            "Sources/Choir/LinguisticFrontend/TextNormalizer.swift",
            "./Sources/Choir/LinguisticFrontend/TextNormalizer.swift",
            r"C:\checkout\Sources\Choir\LinguisticFrontend\TextNormalizer.swift",
        ]

        for path in paths:
            with self.subTest(path=path):
                self.assertTrue(is_linguistic_frontend_source(path))

    def test_rejects_similar_but_different_paths(self) -> None:
        paths = [
            "Sources/Choir/LinguisticFrontendish/TextNormalizer.swift",
            "Sources/Other/LinguisticFrontend/TextNormalizer.swift",
            "Tests/ChoirTests/LinguisticFrontendTests.swift",
            "",
        ]

        for path in paths:
            with self.subTest(path=path):
                self.assertFalse(is_linguistic_frontend_source(path))


if __name__ == "__main__":
    unittest.main()
