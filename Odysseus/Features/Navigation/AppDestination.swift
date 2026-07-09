import SwiftUI

/// The non-chat sections of Odysseus, as shown in the sidebar hub.
enum AppSection: String, CaseIterable, Hashable, Identifiable {
    case brain, notes, calendar, gallery, email, tasks, library, compare, cookbook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brain: "Brain"
        case .notes: "Notes"
        case .calendar: "Calendário"
        case .gallery: "Galeria"
        case .email: "Email"
        case .tasks: "Tasks"
        case .library: "Library"
        case .compare: "Comparar"
        case .cookbook: "Cookbook"
        }
    }

    var icon: String {
        switch self {
        case .brain: "brain"
        case .notes: "note.text"
        case .calendar: "calendar"
        case .gallery: "photo.on.rectangle.angled"
        case .email: "envelope"
        case .tasks: "checklist"
        case .library: "books.vertical"
        case .compare: "rectangle.split.2x1"
        case .cookbook: "fork.knife"
        }
    }

    var subtitle: String {
        switch self {
        case .brain: "Memórias do assistente"
        case .notes: "Anotações e lembretes"
        case .calendar: "Eventos e agenda"
        case .gallery: "Imagens e álbuns"
        case .email: "Caixa de entrada"
        case .tasks: "Agentes agendados"
        case .library: "Documentos pessoais (RAG)"
        case .compare: "Comparar modelos"
        case .cookbook: "Modelos e engines"
        }
    }
}
