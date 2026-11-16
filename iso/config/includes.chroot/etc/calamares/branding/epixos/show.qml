import QtQuick 2.0;
import calamares.slideshow 1.0;

// epixOS — kurulum slaytları.
// slideshowAPI 1: Calamares 3.3.x (Ubuntu noble) ile uyumlu.
Presentation {
    id: presentation

    Timer {
        interval: 12000
        running: true
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        Image {
            anchors.centerIn: parent
            width: 900
            height: 540
            fillMode: Image.PreserveAspectFit
            smooth: true
            source: "slide1.png"
        }
    }

    Slide {
        Image {
            anchors.centerIn: parent
            width: 900
            height: 540
            fillMode: Image.PreserveAspectFit
            smooth: true
            source: "slide2.png"
        }
    }

    Slide {
        Image {
            anchors.centerIn: parent
            width: 900
            height: 540
            fillMode: Image.PreserveAspectFit
            smooth: true
            source: "slide3.png"
        }
    }
}
